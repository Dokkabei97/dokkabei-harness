---
name: analyze
description: "Comprehensive code analysis with quality, security, performance, and architecture assessment"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /analyze - Code Analysis and Quality Assessment

## Triggers
- Code quality assessment requests for projects or specific components
- Security vulnerability scanning and compliance validation needs
- Performance bottleneck identification and optimization planning
- Architecture review and technical debt assessment requirements
## Usage
```
/analyze [target] [options]

Options:
  --focus quality|security|performance|architecture  Analysis domain
  --depth quick|deep                                 Analysis depth
  --format text|json|report                          Output format
```

## Behavioral Flow

### Standard Analysis Flow
1. **Discover**: Categorize source files using language detection and project analysis
2. **Scan**: Apply domain-specific analysis techniques and pattern matching
3. **Evaluate**: Generate prioritized findings with severity ratings and impact assessment
4. **Recommend**: Create actionable recommendations with implementation guidance
5. **Report**: Present comprehensive analysis with metrics and improvement roadmap

## Tool Coordination
- **Glob**: File discovery and project structure analysis
- **Grep**: Pattern analysis and code search operations
- **Read**: Source code inspection and configuration analysis
- **Bash**: External analysis tool execution
- **Write**: Report generation and metrics documentation

## Key Patterns
- **Domain Analysis**: Quality/Security/Performance/Architecture specialized assessment
- **Pattern Recognition**: Language detection with appropriate analysis techniques
- **Severity Assessment**: Issue classification with prioritized recommendations
- **Report Generation**: Analysis results as structured documentation
## Examples

### Comprehensive Project Analysis
```
/analyze
# Multi-domain analysis of entire project
# Generates comprehensive report with key findings and roadmap
```

### Focused Security Assessment
```
/analyze src/auth --focus security --depth deep
# Deep security analysis of authentication components
# Vulnerability assessment with detailed remediation guidance
```

### Performance Optimization Analysis
```
/analyze --focus performance --format report
# Performance bottleneck identification
# Generates report with optimization recommendations
```

### Quick Quality Check
```
/analyze src/components --focus quality --depth quick
# Rapid quality assessment of component directory
# Identifies code smells and maintainability issues
```

## Output Format

### Standard Output (--format text)
```
## Analysis Summary
- Target: [path]
- Focus: [domain]
- Depth: [level]
- Files Analyzed: [count]

## Findings
### Critical (X issues)
- [Finding description] - [File:Line]

### High (X issues)
...

## Recommendations
1. [Priority] [Recommendation]
   - Impact: [description]
   - Effort: [estimate]
```

## Boundaries

**Will:**
- Perform comprehensive static code analysis across multiple domains
- Generate severity-rated findings with actionable recommendations
- Provide detailed reports with metrics and improvement guidance

**Will Not:**
- Execute dynamic analysis requiring code compilation or runtime
- Modify source code or apply fixes without explicit user consent
- Analyze external dependencies beyond import and usage patterns
