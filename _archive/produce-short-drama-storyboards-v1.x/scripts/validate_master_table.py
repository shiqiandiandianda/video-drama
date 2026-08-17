#!/usr/bin/env python3
"""Validate the structural invariants of a 35-column storyboard master table."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path


EXPECTED_COLUMNS = [
    "镜头号",
    "时间段",
    "时长",
    "剧情节点",
    "剧本原句/原动作",
    "出镜角色",
    "说话角色",
    "原始台词",
    "情绪翻译",
    "人物站位图解",
    "空间锚点",
    "起始景别",
    "结束景别",
    "机位高度",
    "机位角度",
    "构图方式",
    "摄像机方案",
    "镜头方案",
    "焦段",
    "帧率/快门",
    "光圈",
    "ISO",
    "白平衡/色温",
    "对焦/景深",
    "摄影参数理由",
    "主推荐运镜",
    "备选运镜A",
    "备选运镜B",
    "运镜推荐理由",
    "首帧关键画面",
    "终帧落点",
    "口型要求",
    "声音设计",
    "参考图需求",
    "风险提示",
]

TIME_RANGE_RE = re.compile(r"^(\d+(?:\.\d+)?)s-(\d+(?:\.\d+)?)s$")
DURATION_RE = re.compile(r"^(\d+(?:\.\d+)?)s$")
SEPARATOR_RE = re.compile(r"^:?-{3,}:?$")


@dataclass
class Result:
    errors: list[str]
    warnings: list[str]


def split_row(line: str) -> list[str]:
    stripped = line.strip()
    if not (stripped.startswith("|") and stripped.endswith("|")):
        return []
    return [cell.strip() for cell in stripped[1:-1].split("|")]


def is_separator(cells: list[str]) -> bool:
    return bool(cells) and all(SEPARATOR_RE.fullmatch(cell) for cell in cells)


def locate_table(lines: list[str]) -> tuple[int, list[str], list[list[str]]] | None:
    for index, line in enumerate(lines[:-1]):
        header = split_row(line)
        separator = split_row(lines[index + 1])
        if "镜头号" not in header or not is_separator(separator):
            continue
        rows: list[list[str]] = []
        for candidate in lines[index + 2 :]:
            cells = split_row(candidate)
            if not cells:
                break
            rows.append(cells)
        return index, header, rows
    return None


def parse_decimal(value: str) -> Decimal | None:
    try:
        return Decimal(value)
    except InvalidOperation:
        return None


def validate(text: str) -> Result:
    errors: list[str] = []
    warnings: list[str] = []
    located = locate_table(text.splitlines())
    if located is None:
        return Result(["未找到以“镜头号”开头且带Markdown分隔行的母表。"], warnings)

    _, header, rows = located
    if header != EXPECTED_COLUMNS:
        errors.append("表头不是固定35列，或列名/顺序有变化。")
        for index, expected in enumerate(EXPECTED_COLUMNS):
            actual = header[index] if index < len(header) else "<缺失>"
            if actual != expected:
                errors.append(f"第{index + 1}列应为“{expected}”，实际为“{actual}”。")
        if len(header) > len(EXPECTED_COLUMNS):
            errors.append(f"存在多余列：{'、'.join(header[len(EXPECTED_COLUMNS):])}")

    if not rows:
        errors.append("母表没有镜头数据行。")
        return Result(errors, warnings)

    previous_shot: int | None = None
    previous_end: Decimal | None = None
    page_start: Decimal | None = None

    for row_number, cells in enumerate(rows, start=1):
        if len(cells) != len(EXPECTED_COLUMNS):
            errors.append(
                f"数据第{row_number}行有{len(cells)}列，应为{len(EXPECTED_COLUMNS)}列。"
            )
            continue

        shot_text, time_text, duration_text = cells[0], cells[1], cells[2]
        if not shot_text.isdigit():
            errors.append(f"数据第{row_number}行镜头号“{shot_text}”不是纯数字。")
            shot = None
        else:
            shot = int(shot_text)
            if previous_shot is not None and shot != previous_shot + 1:
                errors.append(
                    f"镜头号不连续：{previous_shot}之后出现{shot}。"
                )
            previous_shot = shot

        time_match = TIME_RANGE_RE.fullmatch(time_text)
        duration_match = DURATION_RE.fullmatch(duration_text)
        if not time_match:
            errors.append(
                f"镜头{shot_text}时间段“{time_text}”格式错误，应类似0.0s-1.3s。"
            )
            continue
        if not duration_match:
            errors.append(
                f"镜头{shot_text}时长“{duration_text}”格式错误，应类似1.3s。"
            )
            continue

        start = parse_decimal(time_match.group(1))
        end = parse_decimal(time_match.group(2))
        duration = parse_decimal(duration_match.group(1))
        if start is None or end is None or duration is None:
            errors.append(f"镜头{shot_text}时间数值无法解析。")
            continue
        if end <= start:
            errors.append(f"镜头{shot_text}结束时间必须晚于开始时间。")
        if previous_end is not None and start != previous_end:
            errors.append(
                f"镜头{shot_text}从{start}s开始，但上一镜在{previous_end}s结束，时间轴不连续。"
            )
        if end - start != duration:
            errors.append(
                f"镜头{shot_text}时间段为{end - start}s，但时长列写{duration}s。"
            )

        if (row_number - 1) % 10 == 0:
            page_start = start
        if row_number % 10 == 0 and page_start is not None and end - page_start > Decimal("15"):
            errors.append(
                f"默认第{(row_number - 1) // 10 + 1}页的10镜合计{end - page_start}s，超过15s。"
            )
        previous_end = end

    if len(rows) % 10 and page_start is not None and previous_end is not None:
        partial_duration = previous_end - page_start
        if partial_duration > Decimal("15"):
            errors.append(f"末页合计{partial_duration}s，超过15s。")

    if not text.lstrip().startswith("《"):
        warnings.append("未检测到以《开头的母表标题。")
    return Result(errors, warnings)


def build_self_test() -> str:
    row = ["占位"] * len(EXPECTED_COLUMNS)
    row[0:3] = ["1", "0.0s-1.0s", "1.0s"]
    return "《自检母表》\n\n| " + " | ".join(EXPECTED_COLUMNS) + " |\n|" + "|".join(
        ["---"] * len(EXPECTED_COLUMNS)
    ) + "|\n| " + " | ".join(row) + " |\n"


def read_input(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8-sig")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="UTF-8 Markdown文件；使用-读取标准输入")
    parser.add_argument("--self-test", action="store_true", help="运行内置最小自检")
    args = parser.parse_args()

    if not args.self_test and not args.path:
        parser.error("请提供文件路径、-或--self-test")
    text = build_self_test() if args.self_test else read_input(args.path)
    result = validate(text)

    for message in result.errors:
        print(f"错误：{message}")
    for message in result.warnings:
        print(f"警告：{message}")
    if result.errors:
        print(f"校验失败：{len(result.errors)}个错误，{len(result.warnings)}个警告。")
        return 1
    print(f"校验通过：固定35列结构与基础时间轴有效；{len(result.warnings)}个警告。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
