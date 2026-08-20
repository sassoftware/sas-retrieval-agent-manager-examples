"use client";

function getBasePath(): string {
  if (typeof document !== "undefined") {
    return document.documentElement.dataset.basePath || "";
  }

  return "";
}

export function appPath(path: string): string {
  return `${getBasePath()}/${path.replace(/^\/+/, "")}`;
}
