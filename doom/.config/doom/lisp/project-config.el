;;; project-config.el --- Project file discovery -*- lexical-binding: t; -*-

(after! projectile
  (defun my--projectile-find-file-all-a (original &rest args)
    "Run ORIGINAL with ARGS using an explicitly unrestricted file lister.
Doom's generic command can be a function, whereas this Projectile command
passes it directly to an executor accepting strings only. Bind a command
locally so normal project searches retain their ignore rules and caching.
Include hidden and ignored files, but omit Git's internal metadata."
    (let* ((default-directory (projectile-acquire-root))
           (fd (or (executable-find "fd" t) (executable-find "fdfind" t)))
           (rg (unless fd (executable-find "rg" t)))
           (projectile-generic-command
            (cond
             (fd (concat (shell-quote-argument fd)
                         " --type f --color never --hidden --no-ignore --print0 --exclude .git ."))
             (rg (concat (shell-quote-argument rg)
                         " --files --hidden --no-ignore --null --glob '!.git'"))
             (t "find . -type d -name .git -prune -o -type f -print0"))))
      (apply original args)))

  (advice-add 'projectile-find-file-all :around #'my--projectile-find-file-all-a))
