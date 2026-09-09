// UI tests drive a single shared machine resource (the clipboard) through one
// running instance of the sample app, so they must never overlap. The MSTest
// template opts into method-level parallelism by default; this replaces it.
[assembly: DoNotParallelize]
