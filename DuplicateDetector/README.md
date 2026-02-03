# DuplicateDetector
The DuplicateDetector has been refactored from a string-based comparison approach to use **SwiftSyntax AST parsing** combined with **heuristic analysis**. This provides significantly better accuracy and robustness while maintaining a simple, deterministic approach (no ML, no runtime execution).
