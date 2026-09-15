import { existsSync, readFileSync, readdirSync } from "node:fs"
import { homedir } from "node:os"
import { delimiter, join } from "node:path"

function nvmBin(home: string): string | undefined {
  const versionsRoot = join(home, ".nvm", "versions", "node")
  let preferred = ""

  try {
    preferred = readFileSync(join(home, ".nvm", "alias", "default"), "utf8").trim()
  } catch {
    // Fall back to the newest installed version when no default alias exists.
  }

  const preferredBin = join(versionsRoot, preferred, "bin")
  if (preferred && existsSync(preferredBin)) return preferredBin

  try {
    const versions = readdirSync(versionsRoot).sort((left, right) =>
      right.localeCompare(left, undefined, { numeric: true }),
    )
    return versions
      .map((version) => join(versionsRoot, version, "bin"))
      .find(existsSync)
  } catch {
    return undefined
  }
}

function prependPath(paths: Array<string | undefined>, current: string): string {
  return [...new Set([...paths.filter((path): path is string => Boolean(path)), ...current.split(delimiter)])]
    .filter(Boolean)
    .join(delimiter)
}

export const ShellEnvironment = async () => {
  const home = homedir()
  const nodeBin = nvmBin(home)
  const executablePaths = [
    join(home, ".local", "bin"),
    join(home, ".opencode", "bin"),
    join(home, ".ciao", "build", "bin"),
    join(home, "clip", "Systems", "ciao-devel", "build", "bin"),
    nodeBin,
  ].filter((path) => path && existsSync(path))

  return {
    "shell.env": async (_input: unknown, output: { env: Record<string, string> }) => {
      output.env.PATH = prependPath(executablePaths, output.env.PATH ?? process.env.PATH ?? "")
      output.env.NVM_DIR = join(home, ".nvm")
      if (nodeBin) output.env.NVM_BIN = nodeBin
    },
  }
}
