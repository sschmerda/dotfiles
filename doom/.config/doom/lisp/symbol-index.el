;;; symbol-index.el --- Incremental local LSP symbol indexes -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'filenotify)
(require 'json)
(require 'seq)
(eval-when-compile (require 'lsp-mode nil t))
(defvar lsp-response-timeout)

(defcustom my-symbol-index-byte-limit (* 256 1024 1024)
  "Combined disk budget for symbol databases, in bytes. Zero uses memory only."
  :type 'natnum :group 'convenience)

(defvar doom-cache-dir)
(defvar lsp--cur-workspace)
(defvar lsp-use-plists)
(defvar projectile-enable-caching)
(defvar my--index-busy-files (make-hash-table :test #'equal))
(defvar my--symbol-indexes (make-hash-table :test #'equal))
(cl-defstruct (my--index (:constructor my--index-create))
  root database loaded memory-only scanning scan-again snapshot queue flight timer listener watches rescan workspaces
  (files (make-hash-table :test #'equal))
  (errors (make-hash-table :test #'equal)))
(cl-defstruct my--index-file path workspace language provider version hash candidates ready)

(defun my--symbol-cache-directory ()
  (expand-file-name "project-symbols/" (if (boundp 'doom-cache-dir) doom-cache-dir user-emacs-directory)))

(defun my--symbol-cache-path (root)
  (expand-file-name (format "%s-%s.sqlite"
                            (replace-regexp-in-string "[^[:alnum:]_-]" "_"
                                                      (file-name-nondirectory (directory-file-name root)))
                            (secure-hash 'sha256 root))
                    (my--symbol-cache-directory)))

(defun my--symbol-cache-databases ()
  (let ((dir (my--symbol-cache-directory)))
    (when (file-directory-p dir)
      (seq-filter #'file-regular-p
                  (directory-files dir t "\\`[[:alnum:]_-]*-[0-9a-f]\\{64\\}\\.sqlite\\'" t)))))

(defun my--index-get (root)
  (or (when-let ((index (gethash root my--symbol-indexes)))
        (my--index-db index 'touch)
        index)
      (puthash root (my--index-create :root root :database (my--symbol-cache-path root))
               my--symbol-indexes)))

(defun my--index-budget (index)
  "Evict least recently used closed databases after a write."
  (let* ((own (my--index-database index))
         (files (my--symbol-cache-databases))
         (rows (mapcar (lambda (file) (cons file (file-attributes file))) files))
         (bytes (cl-loop for (_ . attrs) in rows sum (file-attribute-size attrs))))
    (when (> (file-attribute-size (file-attributes own)) my-symbol-index-byte-limit)
      (delete-file own)
      (setq bytes (- bytes (file-attribute-size (cdr (assoc own rows))))
            rows (assoc-delete-all own rows))
      (setf (my--index-memory-only index) t))
    (dolist (row (sort rows (lambda (a b)
                              (time-less-p (file-attribute-modification-time (cdr a))
                                           (file-attribute-modification-time (cdr b))))))
      (when (> bytes my-symbol-index-byte-limit)
        (delete-file (car row))
        (cl-decf bytes (file-attribute-size (cdr row)))))))

(defun my--index-db (index action &optional params)
  "Read or change saved-file records under a short shared cache-directory lock."
  (when (and (> my-symbol-index-byte-limit 0) (not (my--index-memory-only index))
             (fboundp 'sqlite-available-p) (sqlite-available-p))
    (let* ((path (my--index-database index))
           (directory (file-name-directory path))
           (guard (expand-file-name "cache-writer" directory)))
      (when (or (eq action 'save) (file-exists-p path))
        (condition-case err
            (progn
              (unless (file-directory-p directory)
                (with-file-modes #o700 (make-directory directory t)))
              (unless (file-locked-p guard)
                (lock-file guard)
                (unwind-protect
                    (let ((db (sqlite-open path)))
                      (unwind-protect
                          (progn
                            (sqlite-execute db "CREATE TABLE IF NOT EXISTS documents
                              (path TEXT PRIMARY KEY, provider TEXT, stamp TEXT, hash TEXT, symbols TEXT)")
                            (pcase action
                              ('touch (set-file-times path))
                              ('load (set-file-times path)
                                     (sqlite-select db "SELECT path,provider,stamp,hash FROM documents"))
                              ('payload (caar (sqlite-select db "SELECT symbols FROM documents WHERE path=? AND provider=? AND stamp=? AND hash=?" params)))
                              ('single (set-file-times path)
                                       (car (sqlite-select db "SELECT path,provider,stamp,hash,symbols FROM documents WHERE path=?" params)))
                              ('stamp (sqlite-execute db "UPDATE documents SET stamp=? WHERE path=? AND hash=?" params))
                              ('drop (sqlite-execute db "DELETE FROM documents WHERE path=?" params))
                              ('save (sqlite-execute db "INSERT OR REPLACE INTO documents VALUES(?,?,?,?,?)" params))))
                        (sqlite-close db)
                        (when (memq action '(touch load save)) (my--index-budget index))))
                  (unlock-file guard))))
          (error (setf (my--index-memory-only index) t)
                 (message "Symbol index using memory for %s: %s" path (error-message-string err))
                 nil))))))

(defun my--index-stamp (path)
  (when-let ((attrs (file-attributes path)))
    (list (file-attribute-modification-time attrs) (file-attribute-status-change-time attrs)
          (file-attribute-size attrs) (file-attribute-inode-number attrs))))

(defun my--index-visiting (path)
  (when-let ((buffer (find-buffer-visiting path)))
    (unless (string-prefix-p " Preview:" (buffer-name buffer)) buffer)))

(defvar-local my--index-saved-check nil)

(defun my--index-buffer-saved-p (buffer path stamp)
  "Check whether BUFFER represents the saved bytes, including coding and EOL.
Memoize by visited file identity and tick so ordinary checks only read metadata."
  (with-current-buffer buffer
    (and stamp (not (buffer-modified-p)) (verify-visited-file-modtime buffer)
         (let ((key (list path stamp (buffer-chars-modified-tick) buffer-file-coding-system)))
           (unless (equal key (car my--index-saved-check))
             (setq my--index-saved-check
                   (cons key
                         (save-restriction
                           (widen)
                           (equal (my--index-hash path)
                                  (secure-hash 'sha256
                                               (encode-coding-string
                                                (buffer-substring-no-properties (point-min) (point-max))
                                                buffer-file-coding-system)))))))
           (cdr my--index-saved-check)))))

(cl-defun my--index-version (path &optional (buffer (my--index-visiting path)))
  (let ((stamp (my--index-stamp path)))
    (if (and buffer (not (my--index-buffer-saved-p buffer path stamp)))
        (list stamp buffer (buffer-chars-modified-tick buffer))
      (list stamp))))

(defun my--index-hash (path)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defun my--index-provider (workspace language)
  (secure-hash
   'sha256 (prin1-to-string
   (list 1 language (lsp--client-server-id (lsp--workspace-client workspace))
         (lsp--workspace-root workspace)
         (lsp-get (lsp--workspace-server-capabilities workspace) :positionEncoding)
         (when-let ((proc (lsp--workspace-cmd-proc workspace)))
           (mapcar (lambda (arg)
                     (if (and (file-name-absolute-p arg) (file-regular-p arg))
                         (list arg (my--index-stamp arg))
                       arg))
                   (process-command proc)))))))

(defun my--index-render (entry response)
  (mapcar (apply-partially #'my--project-symbols-candidate (my--index-file-workspace entry))
          (my--project-symbols-normalize response (lsp--path-to-uri (my--index-file-path entry)))))

(defun my--index-install (index entry response version hash)
  (setf (my--index-snapshot index) nil
        (my--index-file-candidates entry) (my--index-render entry response)
        (my--index-file-ready entry) t
        (my--index-file-version entry) version
        (my--index-file-hash entry) hash)
  (when (and hash (car version) (null (cdr version)))
    (my--index-db index 'save
                  (list (my--index-file-path entry) (my--index-file-provider entry)
                        (prin1-to-string (car version)) hash
                        (json-serialize (vconcat response) :false-object :json-false)))))

(defun my--index-restore (entry row version)
  (pcase-let ((`(,_ ,provider ,stamp ,hash ,payload) row))
    (when (equal provider (my--index-file-provider entry))
      (let ((response (json-parse-string payload :object-type (if lsp-use-plists 'plist 'hash-table)
                                         :false-object :json-false)))
        (setf (my--index-file-candidates entry) (my--index-render entry response)
              (my--index-file-ready entry) t
              (my--index-file-hash entry) hash
              (my--index-file-version entry)
              (and (null (cdr version)) (equal stamp (prin1-to-string (car version))) version))))))

(defun my--index-enqueue (index entry)
  (cl-pushnew entry (my--index-queue index) :test #'eq)
  (when (my--index-listener index) (funcall (my--index-listener index)))
  (unless (or (my--index-flight index) (timerp (my--index-timer index)))
    (setf (my--index-timer index) (run-at-time 0 nil #'my--index-next index))))

(defun my--index-entry (index path context version row)
  (pcase-let* ((`(,workspace ,language ,_) context)
               (provider (my--index-provider workspace language))
               (entry (gethash path (my--index-files index))))
    (unless (and entry (equal provider (my--index-file-provider entry)))
      (setq entry (make-my--index-file :path path :provider provider :workspace workspace :language language))
      (puthash path entry (my--index-files index))
      (setf (my--index-snapshot index) nil)
      (when row
        (condition-case nil
            (let ((record (if (length= row 4)
                              (and (equal provider (nth 1 row))
                                   (append row (list (my--index-db index 'payload row))))
                            row)))
              (when (nth 4 record) (my--index-restore entry record version)))
          (error nil))))
    (setf (my--index-file-workspace entry) workspace)
    entry))

(defun my--index-scan (index &optional verify background first)
  "Reconcile project files, optionally hashing all or yielding between batches.
Visit FIRST before returning so the picker can select the enclosing symbol."
  (if (my--index-scanning index)
      (setf (my--index-scan-again index) (if (or verify (eq (my--index-scan-again index) 'verify)) 'verify t))
    (let* ((visiting (make-hash-table :test #'equal))
           (root (my--index-root index))
           (default-directory root)
           (projectile-enable-caching nil)
           (files (projectile-current-project-files))
           (rows (make-hash-table :test #'equal))
           (seen (make-hash-table :test #'equal))
           (members (make-hash-table :test #'equal))
           (dirs (make-hash-table :test #'equal))
           (exclusions (make-hash-table :test #'equal)))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and buffer-file-name (not (string-prefix-p " Preview:" (buffer-name))))
            (puthash buffer-file-name buffer visiting)
            (when buffer-file-truename (puthash buffer-file-truename buffer visiting)))))
      (unless (my--index-loaded index)
        (dolist (row (my--index-db index 'load)) (puthash (car row) row rows)))
      ;; Restore known files early while the broader directory scan continues.
      (when (> (hash-table-count rows) 0)
        (let (known new)
          (dolist (relative files)
            (if (gethash (expand-file-name relative root) rows)
                (push relative known) (push relative new)))
          (setq files (nconc (nreverse known) (nreverse new)))))
      (cl-labels
          ((visit
             (relative)
             (let ((path (expand-file-name relative root)))
               (unless (my--project-symbols-excluded-p path root exclusions)
                 (puthash path t members)
                 (let ((dir (file-name-directory path)))
                   (while (and dir (not (gethash dir dirs)))
                     (puthash dir t dirs)
                     (setq dir (unless (equal dir root)
                                 (file-name-directory (directory-file-name dir))))))
                 (when-let ((context (my--project-symbols-file-context
                                      path (my--index-workspaces index)
                                      (or (gethash path visiting) (gethash (file-truename path) visiting)))))
                   (let* ((version (my--index-version path (nth 2 context)))
                          (entry (my--index-entry index path context version (gethash path rows))))
                     (when (nth 2 context)
                       (with-current-buffer (nth 2 context) (my--index-track-buffer)))
                     (puthash path t seen)
                     (when (or verify (gethash path (my--index-errors index))
                               (not (equal version (my--index-file-version entry))))
                       (my--index-enqueue index entry)))))))
           (batch
             ()
             (let ((default-directory root) (deadline (+ (float-time) 0.012)))
               (while (and files (or (not background) (< (float-time) deadline)))
                 (let ((file (pop files)))
                   (condition-case err (visit file)
                     (error (let ((path (expand-file-name file root)))
                              (puthash path t seen)
                              (puthash path (format "%s: %s" path (error-message-string err))
                                       (my--index-errors index)))))))
               (if files (run-at-time 0.01 nil (lambda ()
                                                (when (eq index (gethash root my--symbol-indexes))
                                                  (batch))))
                 (dolist (path (delete-dups (append (hash-table-keys rows)
                                                    (hash-table-keys (my--index-files index)))))
                   (unless (gethash path seen)
                     (remhash path (my--index-files index))
                     (remhash path (my--index-errors index))
                     (setf (my--index-snapshot index) nil)
                     (unless (gethash path members) (my--index-db index 'drop (list path)))))
                 (setf (my--index-loaded index) t
                       (my--index-scanning index) nil)
                 (when (my--index-listener index)
                   (my--index-watch index dirs))
                 (when (my--index-scan-again index)
                   (let ((again (my--index-scan-again index)))
                     (setf (my--index-scan-again index) nil)
                     (my--index-scan index (eq again 'verify) t))))
               (when (my--index-listener index) (funcall (my--index-listener index))))))
        (puthash root t dirs)
        (when-let ((relative (and first (file-relative-name first root))))
          (when (member relative files)
            (visit relative)
            (setq files (remove relative files))))
        (setf (my--index-scanning index) t)
        (batch)
        (when-let ((origin (and first (gethash first (my--index-files index)))))
          (when (memq origin (my--index-queue index))
            (setf (my--index-queue index) (cons origin (delq origin (my--index-queue index))))))))))

(defun my--index-schedule-scan (index)
  (when (timerp (my--index-rescan index)) (cancel-timer (my--index-rescan index)))
  (setf (my--index-rescan index)
        (run-at-time 0.35 nil (lambda ()
                                (when (my--index-listener index)
                                  (my--index-scan index nil t)
                                  (funcall (my--index-listener index)))))))

(defun my--index-watch (index dirs)
  (dolist (watch (my--index-watches index))
    (unless (gethash (car watch) dirs)
      (file-notify-rm-watch (cdr watch))
      (setf (my--index-watches index) (delq watch (my--index-watches index)))))
  (maphash
   (lambda (dir _)
     (unless (assoc dir (my--index-watches index))
       (condition-case nil
           (push
            (cons dir (file-notify-add-watch
                       dir '(change)
                       (lambda (event)
                         (when (my--index-listener index)
                           (pcase (cadr event)
                             ((or 'created 'deleted 'renamed) (my--index-schedule-scan index))
                             ('changed
                              (when-let ((entry (gethash (nth 2 event) (my--index-files index))))
                                (my--index-enqueue index entry))))))))
            (my--index-watches index))
         (file-notify-error nil))))
   dirs))

(defun my--index-next (index)
  (setf (my--index-timer index) nil)
  (if (and (my--index-queue index)
           (gethash (my--index-file-path (car (my--index-queue index))) my--index-busy-files))
      ;; Two overlapping Projectile roots can share an LSP document.
      (setf (my--index-timer index) (run-at-time 0.05 nil #'my--index-next index))
    (when-let ((entry (pop (my--index-queue index))))
      (let* ((path (my--index-file-path entry))
             (workspace (my--index-file-workspace entry))
             (version (my--index-version path))
             (buffer (my--index-visiting path))
             (uri (lsp--path-to-uri path))
             (token (make-symbol "symbol-index-request"))
             temporary timeout done hash)
        (cl-labels
            ((finish
               (response failure)
               (unless done
                 (setq done t)
                 (when timeout (cancel-timer timeout))
                 (when temporary (my--project-symbols-close-document path workspace))
                 (unwind-protect
                     (when (eq entry (gethash path (my--index-files index)))
                       (condition-case err
                           (cond
                            (failure (puthash path (format "%s: %s" path failure) (my--index-errors index)))
                            ((or (not (eq workspace (my--index-file-workspace entry)))
                                 (not (equal version (my--index-version path))))
                             (my--index-enqueue index entry))
                            (t (unless (eq response :reuse)
                                 (my--index-install index entry response version hash))
                               (setf (my--index-file-version entry) version)
                               (remhash path (my--index-errors index))))
                         (error (puthash path (error-message-string err) (my--index-errors index)))))
                   (remhash path my--index-busy-files)
                   (setf (my--index-flight index) nil)
                   (when (my--index-queue index)
                     (setf (my--index-timer index) (run-at-time 0 nil #'my--index-next index)))
                   (when (my--index-listener index) (funcall (my--index-listener index)))))))
          (puthash path (lambda ()
                          (unwind-protect (ignore-errors (lsp-cancel-request-by-token token))
                            (finish nil "Index cleared")))
                   my--index-busy-files)
          (setf (my--index-flight index) entry)
          (condition-case err
              (cond
               ((not (eq entry (gethash path (my--index-files index)))) (finish :reuse nil))
               ((and (cdr version) (my--index-file-ready entry)
                     (equal version (my--index-file-version entry)))
                (finish :reuse nil))
               ((and (null (cdr version))
                     (setq hash (my--index-hash path))
                     (my--index-file-ready entry)
                     (equal hash (my--index-file-hash entry)))
                (finish :reuse nil)
                (my--index-db index 'stamp (list (prin1-to-string (car version)) path hash)))
               (t
                (let ((lsp--cur-workspace workspace))
                  (setq temporary (my--project-symbols-open-document
                                   path workspace (my--index-file-language entry) buffer))
                  (when lsp-response-timeout
                    (setq timeout (run-at-time
                                   lsp-response-timeout nil
                                   (lambda () (ignore-errors (lsp-cancel-request-by-token token))
                                     (finish nil "Language server timed out")))))
                  (lsp-request-async "textDocument/documentSymbol" (list :textDocument (list :uri uri))
                                     (lambda (response) (finish response nil)) :mode 'detached
                                     :error-handler (lambda (error) (finish nil error)) :cancel-token token))))
            (error (finish nil (error-message-string err)))))))))

(defun my--index-candidates (index)
  (cl-loop for entry being the hash-values of (my--index-files index)
           append (my--index-file-candidates entry)))

(defun my--index-unwatch (index)
  (setf (my--index-listener index) nil)
  (dolist (watch (my--index-watches index)) (file-notify-rm-watch (cdr watch)))
  (setf (my--index-watches index) nil)
  (when (timerp (my--index-rescan index)) (cancel-timer (my--index-rescan index))))

(defvar-local my--index-edit-timer nil)

(defun my--index-buffer-changed (&rest _)
  (when (timerp my--index-edit-timer) (cancel-timer my--index-edit-timer))
  (let ((path buffer-file-name))
    (setq my--index-edit-timer
          (run-at-time
           0.4 nil
           (lambda ()
             (maphash (lambda (_ index)
                        (when-let ((entry (gethash path (my--index-files index))))
                          (unless (equal (my--index-version path) (my--index-file-version entry))
                            (my--index-enqueue index entry))))
                      my--symbol-indexes))))))

(defun my--index-track-buffer ()
  (when buffer-file-name
    (add-hook 'after-change-functions #'my--index-buffer-changed nil t)
    (add-hook 'after-save-hook #'my--index-buffer-changed nil t)
    (add-hook 'after-revert-hook #'my--index-buffer-changed nil t)
    (add-hook 'kill-buffer-hook #'my--index-buffer-changed nil t)))

(defun my--index-track-known-buffer ()
  (when (and buffer-file-name
             (cl-loop for index being the hash-values of my--symbol-indexes
                      thereis (gethash buffer-file-name (my--index-files index))))
    (my--index-track-buffer)))

(add-hook 'lsp-managed-mode-hook #'my--index-track-known-buffer)

(defun my--index-workspace-stopped (workspace)
  "Release live documents owned by a stopped server; saved rows remain reusable."
  (maphash
   (lambda (root index)
     (setf (my--index-workspaces index) (delq workspace (my--index-workspaces index)))
     (dolist (file (hash-table-keys (my--index-files index)))
       (when (eq workspace (my--index-file-workspace (gethash file (my--index-files index))))
         (remhash file (my--index-files index))
         (remhash file (my--index-errors index))
         (setf (my--index-snapshot index) nil)))
     (when (my--index-listener index) (funcall (my--index-listener index)))
     (unless (or (my--index-workspaces index) (my--index-listener index)
                 (> (hash-table-count (my--index-files index)) 0))
       (remhash root my--symbol-indexes)))
   my--symbol-indexes))

(add-hook 'lsp-after-uninitialized-functions #'my--index-workspace-stopped)

(defun my--index-buffer (index path workspace language buffer)
  "Obtain one current document without enumerating the project."
  (when (gethash path my--index-busy-files)
    (let ((deadline (+ (float-time) (or lsp-response-timeout 10))))
      (while (and (gethash path my--index-busy-files) (< (float-time) deadline))
        (accept-process-output nil 0.02))
      (when (gethash path my--index-busy-files)
        (user-error "Symbol file is still refreshing"))))
  (let* ((version (my--index-version path))
         (entry (my--index-entry index path (list workspace language buffer) version
                                 (unless (gethash path (my--index-files index))
                                   (my--index-db index 'single (list path))))))
    (unless (and (my--index-file-ready entry) (equal version (my--index-file-version entry))
                 (not (gethash path (my--index-errors index)))
                 (or (cdr version) (not (memq entry (my--index-queue index)))
                     (equal (my--index-file-hash entry) (my--index-hash path))))
      (let* ((hash (and (car version) (null (cdr version)) (my--index-hash path)))
             (response (progn
                         (puthash path t my--index-busy-files)
                         (unwind-protect
                             (my--project-symbols-document path workspace language buffer)
                           (remhash path my--index-busy-files)))))
        (unless (equal version (my--index-version path))
          (user-error "Document changed during symbol collection. Open the picker again"))
        (my--index-install index entry response version hash)
        (remhash path (my--index-errors index))))
    (my--index-file-candidates entry)))

(when (fboundp 'set-popup-rule!)
  (set-popup-rule! "^\\*Symbol cache\\*$" :side 'bottom :size 0.35 :select t :quit t :ttl nil))

(define-derived-mode my--symbol-cache-mode special-mode "Symbol cache"
  "Inspect the local symbol cache. Press g to refresh and q to close.")

(defun my--symbol-cache-help ()
  (interactive)
  (describe-function #'my/symbol-cache-status))

(define-key my--symbol-cache-mode-map (kbd "C-c C-h") #'my--symbol-cache-help)
(define-key my--symbol-cache-mode-map (kbd "g") #'my/symbol-cache-status)

(defun my/symbol-cache-status ()
  "Show each project's database size and total disk usage against the budget.
Loaded indexes also show the number of documents held in this Emacs session.
Disk-only projects are identified by database name and abbreviated root hash.
In the report, g refreshes, q closes, and C-c C-h shows this help.
Use M-x my/symbol-cache-clear to clear the current project, or prefix it
with C-u to clear all projects."
  (interactive)
  (let ((projects (make-hash-table :test #'equal)) (total 0) rows
        (origin default-directory))
    (dolist (file (my--symbol-cache-databases)) (puthash file nil projects))
    (maphash (lambda (_ index) (puthash (my--index-database index) index projects))
             my--symbol-indexes)
    (maphash
     (lambda (file index)
       (let* ((bytes (or (file-attribute-size (file-attributes file)) 0))
              (name (if index (abbreviate-file-name (my--index-root index))
                      (substring (file-name-base file) 0 -56))))
         (cl-incf total bytes)
         (push (format "%10s  %12s  %s\n" (file-size-human-readable bytes 'iec)
                       (if index (hash-table-count (my--index-files index)) "—") name)
               rows)))
     projects)
    (with-current-buffer (get-buffer-create "*Symbol cache*")
      (my--symbol-cache-mode)
      (setq default-directory origin)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Disk usage  %s of %s (%d bytes used)\n%s\n\n"
                        (file-size-human-readable total 'iec)
                        (file-size-human-readable my-symbol-index-byte-limit 'iec)
                        total (abbreviate-file-name (my--symbol-cache-directory))))
        (if rows
            (progn (insert "      Disk   Loaded docs  Project\n")
                   (dolist (row (sort rows #'string-lessp)) (insert row)))
          (insert "No cached projects.\n"))
        (insert "\ng refresh   q close   C-c C-h help\n")
        (goto-char (point-min)))
      (pop-to-buffer (current-buffer)))))

(defun my--symbol-cache-forget (index)
  "Stop INDEX and discard its session data before removing its database."
  (let ((listener (my--index-listener index))
        (entry (my--index-flight index)))
    (remhash (my--index-root index) my--symbol-indexes)
    (my--index-unwatch index)
    (when (timerp (my--index-timer index)) (cancel-timer (my--index-timer index)))
    (setf (my--index-memory-only index) t
          (my--index-queue index) nil
          (my--index-scanning index) nil
          (my--index-snapshot index) nil)
    (clrhash (my--index-files index))
    (clrhash (my--index-errors index))
    (when entry
      (let ((cancel (gethash (my--index-file-path entry) my--index-busy-files)))
        (when (functionp cancel) (funcall cancel))))
    (when listener (funcall listener))))

(defun my/symbol-cache-clear (&optional all)
  "Clear the current project's symbol index from this Emacs session and disk.
With prefix ALL, clear every local project index. The next symbol search
rebuilds cleared entries. Use M-x my/symbol-cache-status to inspect usage."
  (interactive "P")
  (let* ((root (unless all
                 (when (file-remote-p default-directory) (user-error "Select a local project"))
                 (file-name-as-directory
                  (or (and (require 'projectile nil t) (projectile-project-root))
                      (when-let ((workspace (car (bound-and-true-p lsp--buffer-workspaces))))
                        (lsp--workspace-root workspace))
                      default-directory))))
         (dir (my--symbol-cache-directory))
         (guard (expand-file-name "cache-writer" dir))
         (locked nil))
    (unwind-protect
        (progn
          (when (file-directory-p dir)
            (when (file-locked-p guard) (user-error "Symbol cache is busy. Try again"))
            (lock-file guard)
            (setq locked t))
          (let ((files (if all (my--symbol-cache-databases) (list (my--symbol-cache-path root))))
                (indexes (if all (hash-table-values my--symbol-indexes)
                           (delq nil (list (gethash root my--symbol-indexes))))))
            (mapc #'my--symbol-cache-forget indexes)
            (dolist (file files)
              (dolist (suffix '("-journal" "-wal" "-shm" ""))
                (let ((path (concat file suffix)))
                  (when (file-exists-p path) (delete-file path)))))))
      (when locked (unlock-file guard)))
    (message "Symbol cache cleared for %s" (if all "all local projects" root))))

(provide 'symbol-index)
;;; symbol-index.el ends here
