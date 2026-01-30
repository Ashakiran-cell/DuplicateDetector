import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - DuplicateDetector v2: SwiftSyntax + Heuristic Analysis
// 
// REFACTORING NOTES:
// ==================
// This tool was refactored from string-based comparison to AST-based heuristic analysis
// using SwiftSyntax and SwiftParser. The new approach provides:
//
// 1. ACCURATE AST PARSING
//    - Uses SwiftSyntax to parse Swift source code into Abstract Syntax Trees
//    - Properly handles function declarations, expressions, and control flow
//    - More robust than regex/string matching against various formatting styles
//
// 2. HEURISTIC SIGNATURE EXTRACTION
//    - Captures: operators, function calls, control flow keywords, structural patterns
//    - Ignores: variable names, function parameter names, formatting, comments
//    - Enables detection of logic duplicates with different variable names
//
// 3. WEIGHTED SIMILARITY SCORING
//    - Operators (30%): +, -, *, /, %, ==, <, >, etc.
//    - Function Calls (25%): print(), map(), filter(), custom functions
//    - Control Flow (20%): if, while, for, switch, return patterns
//    - Structure (25%): assignment count, loop count, condition count
//    - Threshold: 70% match = likely duplicate (tunable)
//
// 4. XCODE INTEGRATION
//    - Outputs Xcode-compatible warnings to stdout and stderr
//    - Shows similarity percentage for validation
//    - Includes file paths and line numbers for navigation
//
// ADVANTAGES OVER STRING-BASED APPROACH:
// ======================================
// ✓ Handles different formatting (spaces, indentation, etc.)
// ✓ Ignores variable/parameter name changes
// ✓ More semantically accurate (analyzes actual code structure)
// ✓ No false positives from comments or string literals
// ✓ Foundation for future enhancements (partial duplicates, refactoring suggestions)
//
// LIMITATIONS (by design):
// ========================
// • Does NOT detect semantic equivalents (e.g., `x * (x+1) / 2` vs loop summing)
// • No runtime execution or symbolic evaluation
// • No machine learning (deterministic heuristics only)

// MARK: - Utilities

func getLineNumber(from position: AbsolutePosition, in source: String) -> Int {
    // Convert UTF8 offset to line number by counting newlines before the position
    var lineCount = 1
    var utf8Count = 0
    
    for char in source {
        if utf8Count >= position.utf8Offset {
            break
        }
        if char == "\n" {
            lineCount += 1
        }
        utf8Count += char.utf8.count
    }
    
    return lineCount
}

func getLineNumberForFunctionDeclaration(from position: AbsolutePosition, in source: String) -> Int {
    // Get the rough line number
    let roughLine = getLineNumber(from: position, in: source)
    
    // Find the exact line containing "func" keyword
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    
    // Search nearby lines for the actual "func" keyword
    let searchRange = max(0, roughLine - 3)...min(lines.count - 1, roughLine + 2)
    
    for lineIndex in searchRange {
        let line = lines[lineIndex]
        if line.trimmingCharacters(in: .whitespaces).starts(with: "func ") {
            return lineIndex + 1  // Line numbers are 1-based
        }
    }
    
    return roughLine
}

struct FunctionLocation {
    let file: String
    let line: Int
    let name: String
}

struct HeuristicSignature {
    let operators: Set<String>
    let functionCalls: Set<String>
    let controlFlowKeywords: Set<String>
    let assignmentCount: Int
    let loopCount: Int
    let conditionCount: Int
    let returnStatementCount: Int
    
    func similarity(to other: HeuristicSignature) -> Double {
        let operatorMatch = Double(operators.intersection(other.operators).count) / 
                           Double(max(operators.union(other.operators).count, 1))
        
        let callMatch = Double(functionCalls.intersection(other.functionCalls).count) / 
                       Double(max(functionCalls.union(other.functionCalls).count, 1))
        
        let flowMatch = Double(controlFlowKeywords.intersection(other.controlFlowKeywords).count) / 
                       Double(max(controlFlowKeywords.union(other.controlFlowKeywords).count, 1))
        
        let structuralDiff = abs(Double(assignmentCount - other.assignmentCount)) +
                            abs(Double(loopCount - other.loopCount)) +
                            abs(Double(conditionCount - other.conditionCount)) +
                            abs(Double(returnStatementCount - other.returnStatementCount))
        
        let structuralSimilarity = max(0, 1.0 - (structuralDiff / 10.0))
        
        // Weighted average: operators (30%), calls (25%), flow (20%), structure (25%)
        let totalSimilarity = (operatorMatch * 0.30) +
                             (callMatch * 0.25) +
                             (flowMatch * 0.20) +
                             (structuralSimilarity * 0.25)
        
        return totalSimilarity
    }
}

// MARK: - AST Visitor for Heuristic Extraction

class HeuristicExtractor: SyntaxVisitor {
    var operators: Set<String> = []
    var functionCalls: Set<String> = []
    var controlFlowKeywords: Set<String> = []
    var assignmentCount = 0
    var loopCount = 0
    var conditionCount = 0
    var returnStatementCount = 0
    
    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }
    
    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let op = node.operator.text
        operators.insert(op)
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            functionCalls.insert(identifier.baseName.text)
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            functionCalls.insert(member.declName.baseName.text)
        }
        return .visitChildren
    }
    
    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        assignmentCount += 1
        return .visitChildren
    }
    
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        loopCount += 1
        controlFlowKeywords.insert("for")
        return .visitChildren
    }
    
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        loopCount += 1
        controlFlowKeywords.insert("while")
        return .visitChildren
    }
    
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        conditionCount += 1
        controlFlowKeywords.insert("if")
        return .visitChildren
    }
    
    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        returnStatementCount += 1
        controlFlowKeywords.insert("return")
        return .visitChildren
    }
    
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        conditionCount += 1
        controlFlowKeywords.insert("switch")
        return .visitChildren
    }
    
    func getSignature() -> HeuristicSignature {
        return HeuristicSignature(
            operators: operators,
            functionCalls: functionCalls,
            controlFlowKeywords: controlFlowKeywords,
            assignmentCount: assignmentCount,
            loopCount: loopCount,
            conditionCount: conditionCount,
            returnStatementCount: returnStatementCount
        )
    }
}

// MARK: - Function Extraction with SwiftSyntax

func extractFunctionsWithAST(
    from filePath: String,
    handler: (String, HeuristicSignature, Int) -> Void
) {
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        return
    }
    
    let sourceFile = Parser.parse(source: source)
    let collector = FunctionCollector(source: source)
    collector.walk(sourceFile)
    
    for funcInfo in collector.functions {
        handler(funcInfo.name, funcInfo.signature, funcInfo.line)
    }
}

class FunctionCollector: SyntaxVisitor {
    struct FunctionInfo {
        let name: String
        let signature: HeuristicSignature
        let line: Int
    }
    
    var functions: [FunctionInfo] = []
    let source: String
    
    init(source: String) {
        self.source = source
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        
        // Get accurate line number pointing to the "func" keyword
        let line = getLineNumberForFunctionDeclaration(from: node.position, in: source)
        
        // Extract heuristics from function body
        let extractor = HeuristicExtractor()
        if let body = node.body {
            extractor.walk(body)
        }
        
        let signature = extractor.getSignature()
        functions.append(FunctionInfo(name: name, signature: signature, line: line))
        
        return .skipChildren
    }
}

// MARK: - Entry Point

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty { exit(0) }

var inputPaths: [String] = []
var outputStamp: String?

var i = 0
while i < args.count {
    if args[i] == "-o", i + 1 < args.count {
        outputStamp = args[i + 1]
        i += 2
    } else {
        inputPaths.append(args[i])
        i += 1
    }
}

let swiftFiles = inputPaths.filter { $0.hasSuffix(".swift") }

// MARK: - Split files by type

var extensionFiles: [String] = []
var nonExtensionFiles: [String] = []

for path in swiftFiles {
    if let content = try? String(contentsOfFile: path) {
        if content.contains("extension ") {
            extensionFiles.append(path)
        } else {
            nonExtensionFiles.append(path)
        }
    } else {
        nonExtensionFiles.append(path)
    }
}

// MARK: - Phase 1: Collect extension logic

var extensionFunctions: [String: (location: FunctionLocation, signature: HeuristicSignature)] = [:]

for path in extensionFiles {
    extractFunctionsWithAST(from: path) { name, signature, line in
        let key = "\(path):\(line):\(name)"
        extensionFunctions[key] = (
            location: FunctionLocation(file: path, line: line, name: name),
            signature: signature
        )
    }
}

// MARK: - Phase 2: Detect duplicates in non-extension files

let SIMILARITY_THRESHOLD = 0.70  // 70% heuristic match indicates likely duplicate

var warnings: [String] = []

for path in nonExtensionFiles {
    extractFunctionsWithAST(from: path) { name, signature, line in
        // Compare against all extension functions
        for (_, extFuncData) in extensionFunctions {
            let similarity = signature.similarity(to: extFuncData.signature)
            
            if similarity >= SIMILARITY_THRESHOLD {
                let warning = "\(path):\(line): warning: Duplicate function '\(name)' detected " +
                             "(similarity: \(String(format: "%.0f", similarity * 100))%). " +
                             "Similar logic exists in \(extFuncData.location.file):\(extFuncData.location.line)"
                
                warnings.append(warning)
                break  // Only report once per function
            }
        }
    }
}

// MARK: - Phase 3: Detect duplicates within extension files

for path in extensionFiles {
    var foundFunctions: [(name: String, signature: HeuristicSignature, line: Int)] = []
    
    extractFunctionsWithAST(from: path) { name, signature, line in
        // Compare with previously found functions in same file
        for prevFunc in foundFunctions {
            let similarity = signature.similarity(to: prevFunc.signature)
            
            if similarity >= SIMILARITY_THRESHOLD {
                let warning = "\(path):\(line): warning: Duplicate function '\(name)' detected " +
                             "(similarity: \(String(format: "%.0f", similarity * 100))%). " +
                             "Similar logic exists in \(path):\(prevFunc.line)"
                
                warnings.append(warning)
                break
            }
        }
        
        foundFunctions.append((name: name, signature: signature, line: line))
    }
}

// MARK: - Emit warnings

for w in warnings {
    let warningOutput = w + "\n"
    FileHandle.standardOutput.write(warningOutput.data(using: .utf8)!)
    FileHandle.standardError.write(warningOutput.data(using: .utf8)!)
}

// MARK: - Touch output stamp

if let stamp = outputStamp {
    try? Data().write(to: URL(fileURLWithPath: stamp))
}
