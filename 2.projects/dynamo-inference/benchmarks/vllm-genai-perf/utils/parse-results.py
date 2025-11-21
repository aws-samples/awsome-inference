#!/usr/bin/env python3
"""
Parse and analyze benchmark results from JSON files
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Any
from tabulate import tabulate


def load_json_results(file_path: Path) -> Dict[str, Any]:
    """Load results from a JSON file."""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading {file_path}: {e}", file=sys.stderr)
        return {}


def parse_vllm_results(results_dir: Path) -> List[Dict[str, Any]]:
    """Parse vLLM benchmark results."""
    parsed_results = []

    for json_file in results_dir.glob("**/*.json"):
        data = load_json_results(json_file)
        if not data:
            continue

        result = {
            "file": json_file.name,
            "type": "vllm",
            "metrics": {}
        }

        # Extract common metrics
        for metric in ["request_throughput", "output_token_throughput",
                      "ttft_p50", "ttft_p90", "ttft_p99",
                      "itl_p50", "itl_p90", "itl_p99",
                      "tpot_p50", "e2el_p50"]:
            if metric in data:
                result["metrics"][metric] = data[metric]

        parsed_results.append(result)

    return parsed_results


def parse_genai_perf_results(results_dir: Path) -> List[Dict[str, Any]]:
    """Parse GenAI-Perf benchmark results."""
    parsed_results = []

    for json_file in results_dir.glob("**/exports/*.json"):
        data = load_json_results(json_file)
        if not data:
            continue

        result = {
            "file": json_file.name,
            "type": "genai-perf",
            "metrics": data
        }

        parsed_results.append(result)

    return parsed_results


def format_results_table(results: List[Dict[str, Any]]) -> str:
    """Format results as a table."""
    if not results:
        return "No results found"

    headers = ["File", "Type"]
    metrics_keys = set()
    for result in results:
        metrics_keys.update(result["metrics"].keys())

    headers.extend(sorted(metrics_keys))

    rows = []
    for result in results:
        row = [result["file"], result["type"]]
        for metric in sorted(metrics_keys):
            value = result["metrics"].get(metric, "N/A")
            if isinstance(value, float):
                row.append(f"{value:.2f}")
            else:
                row.append(str(value))
        rows.append(row)

    return tabulate(rows, headers=headers, tablefmt="grid")


def calculate_summary_stats(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate summary statistics across all results."""
    summary = {}

    # Collect all metric values
    metric_values = {}
    for result in results:
        for metric, value in result["metrics"].items():
            if isinstance(value, (int, float)):
                if metric not in metric_values:
                    metric_values[metric] = []
                metric_values[metric].append(value)

    # Calculate stats for each metric
    for metric, values in metric_values.items():
        if not values:
            continue

        summary[metric] = {
            "min": min(values),
            "max": max(values),
            "mean": sum(values) / len(values),
            "count": len(values)
        }

    return summary


def main():
    parser = argparse.ArgumentParser(description="Parse benchmark results")
    parser.add_argument("results_dir", type=Path, help="Results directory")
    parser.add_argument("--format", choices=["table", "json", "summary"],
                       default="table", help="Output format")
    parser.add_argument("--output", type=Path, help="Output file (default: stdout)")

    args = parser.parse_args()

    if not args.results_dir.exists():
        print(f"Error: Results directory not found: {args.results_dir}", file=sys.stderr)
        sys.exit(1)

    # Parse results
    print("Parsing results...", file=sys.stderr)
    vllm_results = parse_vllm_results(args.results_dir)
    genai_perf_results = parse_genai_perf_results(args.results_dir)

    all_results = vllm_results + genai_perf_results

    if not all_results:
        print("No results found", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(all_results)} result files", file=sys.stderr)

    # Format output
    output_content = ""

    if args.format == "table":
        output_content = format_results_table(all_results)
    elif args.format == "json":
        output_content = json.dumps(all_results, indent=2)
    elif args.format == "summary":
        summary = calculate_summary_stats(all_results)
        output_content = "Summary Statistics\n"
        output_content += "=" * 50 + "\n\n"
        for metric, stats in sorted(summary.items()):
            output_content += f"{metric}:\n"
            output_content += f"  Min:   {stats['min']:.2f}\n"
            output_content += f"  Max:   {stats['max']:.2f}\n"
            output_content += f"  Mean:  {stats['mean']:.2f}\n"
            output_content += f"  Count: {stats['count']}\n\n"

    # Write output
    if args.output:
        args.output.write_text(output_content)
        print(f"Results written to: {args.output}", file=sys.stderr)
    else:
        print(output_content)


if __name__ == "__main__":
    main()
