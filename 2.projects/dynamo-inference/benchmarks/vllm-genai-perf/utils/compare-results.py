#!/usr/bin/env python3
"""
Compare benchmark results across multiple runs
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Any
from tabulate import tabulate


def load_result_files(result_paths: List[Path]) -> List[Dict[str, Any]]:
    """Load results from multiple files."""
    results = []
    for path in result_paths:
        try:
            with open(path, 'r') as f:
                data = json.load(f)
                data['_file'] = path.name
                results.append(data)
        except Exception as e:
            print(f"Warning: Could not load {path}: {e}", file=sys.stderr)
    return results


def compare_metrics(results: List[Dict[str, Any]], metrics: List[str]) -> str:
    """Compare specific metrics across results."""
    if not results:
        return "No results to compare"

    # Build comparison table
    headers = ["File"] + metrics
    rows = []

    for result in results:
        row = [result.get('_file', 'unknown')]
        for metric in metrics:
            value = result.get(metric, 'N/A')
            if isinstance(value, float):
                row.append(f"{value:.2f}")
            else:
                row.append(str(value))
        rows.append(row)

    return tabulate(rows, headers=headers, tablefmt="grid")


def calculate_improvements(baseline: Dict[str, Any],
                          comparison: Dict[str, Any]) -> Dict[str, float]:
    """Calculate percentage improvements from baseline."""
    improvements = {}

    for metric in baseline.keys():
        if metric.startswith('_'):
            continue

        baseline_val = baseline.get(metric)
        comparison_val = comparison.get(metric)

        if not isinstance(baseline_val, (int, float)) or \
           not isinstance(comparison_val, (int, float)):
            continue

        if baseline_val == 0:
            continue

        # For latency metrics (lower is better), invert the calculation
        if 'latency' in metric.lower() or 'ttft' in metric.lower() or \
           'itl' in metric.lower() or 'time' in metric.lower():
            improvement = ((baseline_val - comparison_val) / baseline_val) * 100
        else:
            # For throughput metrics (higher is better)
            improvement = ((comparison_val - baseline_val) / baseline_val) * 100

        improvements[metric] = improvement

    return improvements


def main():
    parser = argparse.ArgumentParser(description="Compare benchmark results")
    parser.add_argument("result_files", nargs='+', type=Path,
                       help="Result files to compare")
    parser.add_argument("--metrics", nargs='+',
                       default=["request_throughput", "ttft_p99", "itl_p50"],
                       help="Metrics to compare")
    parser.add_argument("--baseline", type=int, default=0,
                       help="Index of baseline result (default: 0)")
    parser.add_argument("--output", type=Path,
                       help="Output file (default: stdout)")

    args = parser.parse_args()

    # Validate files exist
    for path in args.result_files:
        if not path.exists():
            print(f"Error: File not found: {path}", file=sys.stderr)
            sys.exit(1)

    # Load results
    results = load_result_files(args.result_files)

    if not results:
        print("Error: No valid results loaded", file=sys.stderr)
        sys.exit(1)

    # Generate comparison
    output_content = "Benchmark Results Comparison\n"
    output_content += "=" * 70 + "\n\n"

    # Metric comparison table
    output_content += "Metric Comparison:\n"
    output_content += "-" * 70 + "\n"
    output_content += compare_metrics(results, args.metrics) + "\n\n"

    # Calculate improvements if baseline specified
    if args.baseline < len(results):
        baseline = results[args.baseline]
        output_content += f"Improvements vs Baseline ({baseline['_file']}):\n"
        output_content += "-" * 70 + "\n\n"

        for i, result in enumerate(results):
            if i == args.baseline:
                continue

            improvements = calculate_improvements(baseline, result)
            output_content += f"{result['_file']}:\n"

            for metric, improvement in sorted(improvements.items()):
                sign = "+" if improvement > 0 else ""
                output_content += f"  {metric}: {sign}{improvement:.2f}%\n"

            output_content += "\n"

    # Write output
    if args.output:
        args.output.write_text(output_content)
        print(f"Comparison written to: {args.output}", file=sys.stderr)
    else:
        print(output_content)


if __name__ == "__main__":
    main()
