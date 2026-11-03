package landscape

import "fmt"

const Limit = 42
// Region describes a landscape.
type Region struct { Name string }
func (r Region) Describe() string { return fmt.Sprintf("%s\n", r.Name) }
