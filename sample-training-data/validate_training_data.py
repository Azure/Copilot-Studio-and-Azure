#!/usr/bin/env python3
"""
Data validation script for Azure AI Foundry fine-tuning datasets.
Validates JSONL format, token counts, and data quality.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Any
import re

def count_tokens_approximate(text: str) -> int:
    """
    Approximate token count using a simple heuristic.
    Real tokenizers may vary, but this gives a good estimate.
    """
    # Remove extra whitespace and split on word boundaries
    words = re.findall(r'\b\w+\b', text.lower())
    # Rough estimate: 1 token per word + some for punctuation/formatting
    return len(words) + int(len(text) * 0.1)

def validate_jsonl_format(file_path: Path) -> Dict[str, Any]:
    """Validate JSONL file format and structure."""
    results = {
        'valid': True,
        'total_lines': 0,
        'valid_lines': 0,
        'errors': [],
        'warnings': [],
        'token_stats': {
            'min_tokens': float('inf'),
            'max_tokens': 0,
            'total_tokens': 0,
            'avg_tokens': 0
        }
    }
    
    if not file_path.exists():
        results['valid'] = False
        results['errors'].append(f"File not found: {file_path}")
        return results
    
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            for line_num, line in enumerate(file, 1):
                results['total_lines'] = line_num
                line = line.strip()
                
                if not line:
                    continue
                
                try:
                    # Parse JSON
                    data = json.loads(line)
                    
                    # Validate structure
                    validation_result = validate_training_example(data, line_num)
                    
                    if validation_result['valid']:
                        results['valid_lines'] += 1
                        
                        # Count tokens
                        tokens = count_example_tokens(data)
                        results['token_stats']['min_tokens'] = min(results['token_stats']['min_tokens'], tokens)
                        results['token_stats']['max_tokens'] = max(results['token_stats']['max_tokens'], tokens)
                        results['token_stats']['total_tokens'] += tokens
                    else:
                        results['valid'] = False
                        results['errors'].extend(validation_result['errors'])
                    
                    results['warnings'].extend(validation_result['warnings'])
                    
                except json.JSONDecodeError as e:
                    results['valid'] = False
                    results['errors'].append(f"Line {line_num}: Invalid JSON - {e}")
                
    except Exception as e:
        results['valid'] = False
        results['errors'].append(f"Error reading file: {e}")
    
    # Calculate averages
    if results['valid_lines'] > 0:
        results['token_stats']['avg_tokens'] = results['token_stats']['total_tokens'] / results['valid_lines']
    
    if results['token_stats']['min_tokens'] == float('inf'):
        results['token_stats']['min_tokens'] = 0
    
    return results

def validate_training_example(data: Dict[str, Any], line_num: int) -> Dict[str, Any]:
    """Validate a single training example."""
    result = {'valid': True, 'errors': [], 'warnings': []}
    
    # Check for required fields
    if 'messages' not in data:
        result['valid'] = False
        result['errors'].append(f"Line {line_num}: Missing 'messages' field")
        return result
    
    messages = data['messages']
    if not isinstance(messages, list):
        result['valid'] = False
        result['errors'].append(f"Line {line_num}: 'messages' must be a list")
        return result
    
    if len(messages) == 0:
        result['valid'] = False
        result['errors'].append(f"Line {line_num}: 'messages' cannot be empty")
        return result
    
    # Validate message structure
    required_roles = set()
    for i, message in enumerate(messages):
        if not isinstance(message, dict):
            result['valid'] = False
            result['errors'].append(f"Line {line_num}: Message {i} must be a dictionary")
            continue
        
        if 'role' not in message:
            result['valid'] = False
            result['errors'].append(f"Line {line_num}: Message {i} missing 'role' field")
            continue
        
        if 'content' not in message:
            result['valid'] = False
            result['errors'].append(f"Line {line_num}: Message {i} missing 'content' field")
            continue
        
        role = message['role']
        content = message['content']
        
        # Validate role values
        valid_roles = {'system', 'user', 'assistant', 'function'}
        if role not in valid_roles:
            result['valid'] = False
            result['errors'].append(f"Line {line_num}: Invalid role '{role}' in message {i}")
        
        required_roles.add(role)
        
        # Validate content
        if not isinstance(content, str):
            result['valid'] = False
            result['errors'].append(f"Line {line_num}: Content in message {i} must be a string")
        elif len(content.strip()) == 0:
            result['warnings'].append(f"Line {line_num}: Empty content in message {i}")
    
    # Check for recommended conversation structure
    if 'user' not in required_roles:
        result['warnings'].append(f"Line {line_num}: No 'user' message found")
    
    if 'assistant' not in required_roles:
        result['warnings'].append(f"Line {line_num}: No 'assistant' message found")
    
    return result

def count_example_tokens(data: Dict[str, Any]) -> int:
    """Count approximate tokens in a training example."""
    total_tokens = 0
    
    if 'messages' in data:
        for message in data['messages']:
            if 'content' in message and isinstance(message['content'], str):
                total_tokens += count_tokens_approximate(message['content'])
            if 'role' in message:
                total_tokens += count_tokens_approximate(message['role'])
    
    return total_tokens

def print_validation_report(file_path: Path, results: Dict[str, Any]):
    """Print a formatted validation report."""
    print(f"\n{'='*60}")
    print(f"VALIDATION REPORT: {file_path.name}")
    print(f"{'='*60}")
    
    # Overall status
    status = "✅ VALID" if results['valid'] else "❌ INVALID"
    print(f"Status: {status}")
    print(f"Total lines: {results['total_lines']}")
    print(f"Valid examples: {results['valid_lines']}")
    
    if results['valid_lines'] > 0:
        print(f"\nToken Statistics:")
        print(f"  Min tokens per example: {results['token_stats']['min_tokens']}")
        print(f"  Max tokens per example: {results['token_stats']['max_tokens']}")
        print(f"  Average tokens per example: {results['token_stats']['avg_tokens']:.1f}")
        print(f"  Total tokens: {results['token_stats']['total_tokens']}")
        
        # Token limit warnings
        if results['token_stats']['max_tokens'] > 4000:
            print(f"  ⚠️  Warning: Some examples exceed 4K tokens (GPT-3.5-turbo limit)")
        if results['token_stats']['max_tokens'] > 8000:
            print(f"  ⚠️  Warning: Some examples exceed 8K tokens (GPT-4 limit)")
    
    # Errors
    if results['errors']:
        print(f"\n❌ ERRORS ({len(results['errors'])}):")
        for error in results['errors'][:10]:  # Show first 10 errors
            print(f"  • {error}")
        if len(results['errors']) > 10:
            print(f"  ... and {len(results['errors']) - 10} more errors")
    
    # Warnings
    if results['warnings']:
        print(f"\n⚠️  WARNINGS ({len(results['warnings'])}):")
        for warning in results['warnings'][:10]:  # Show first 10 warnings
            print(f"  • {warning}")
        if len(results['warnings']) > 10:
            print(f"  ... and {len(results['warnings']) - 10} more warnings")
    
    # Recommendations
    print(f"\n📋 RECOMMENDATIONS:")
    if results['valid_lines'] < 10:
        print("  • Consider adding more training examples (minimum 10-50 recommended)")
    if results['valid_lines'] > 0:
        avg_tokens = results['token_stats']['avg_tokens']
        if avg_tokens < 50:
            print("  • Examples seem quite short - consider adding more detail")
        elif avg_tokens > 2000:
            print("  • Examples are quite long - consider breaking into smaller parts")
    
    if not results['errors']:
        print("  ✅ File format is valid and ready for fine-tuning!")

def main():
    """Main validation function."""
    if len(sys.argv) != 2:
        print("Usage: python validate_training_data.py <jsonl_file>")
        print("\nExample:")
        print("  python validate_training_data.py customer-support-training-data.jsonl")
        sys.exit(1)
    
    file_path = Path(sys.argv[1])
    
    print("🔍 Validating Azure AI Foundry training data...")
    print(f"File: {file_path}")
    
    results = validate_jsonl_format(file_path)
    print_validation_report(file_path, results)
    
    # Exit with error code if validation failed
    if not results['valid']:
        sys.exit(1)
    
    print(f"\n✨ Validation complete!")

if __name__ == "__main__":
    main()