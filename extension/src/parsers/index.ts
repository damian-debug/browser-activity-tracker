import type { ParsedProject } from "../shared/types";
import { parseFigma } from "./figma";
import { parseBubble } from "./bubble";

type Parser = (url: string) => ParsedProject | null;

const PARSERS: Parser[] = [parseFigma, parseBubble];

export function parseProjectFromUrl(url: string): ParsedProject | null {
  for (const parser of PARSERS) {
    const result = parser(url);
    if (result) return result;
  }
  return null;
}
