#!/usr/bin/env bash
# build-registry.sh —— 扫描技能目录（含 manifest.json 的子目录），打包 zip 并生成 registry.json
# 用法: ./scripts/build-registry.sh <tclaw-skills-dir> [out-dir]
# 产物: <out-dir>/registry.json + <out-dir>/dist/<name>-<version>.zip
# registry 中 downloads.url 存相对路径，客户端按 registry 自身 base URL 解析（多平台适配）。
set -euo pipefail

SKILLS_DIR="${1:?usage: build-registry.sh <tclaw-skills-dir> [out-dir]}"
OUT_DIR="${2:-public}"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v zip >/dev/null || { echo "zip is required" >&2; exit 1; }

mkdir -p "${OUT_DIR}/dist"
# 绝对路径（子 shell 会 cd 到技能目录，zip 目标不能用相对路径）
out_abs="$(cd "${OUT_DIR}" && pwd)"

entries="[]"
count=0
for manifest in "${SKILLS_DIR}"/*/manifest.json; do
  [ -f "${manifest}" ] || continue
  skill_dir="$(cd "$(dirname "${manifest}")" && pwd)"
  name="$(jq -r '.name' "${manifest}")"
  version="$(jq -r '.version' "${manifest}")"
  if [ -z "${name}" ] || [ "${name}" = "null" ] || [ -z "${version}" ] || [ "${version}" = "null" ]; then
    echo "WARN: skip ${manifest}: missing name/version" >&2
    continue
  fi

  zip_name="${name}-${version}.zip"
  zip_path="${out_abs}/dist/${zip_name}"
  # zip 根 = 技能目录内容（SKILL.toml/SKILL.md/manifest.json 均在归档根）
  (cd "${skill_dir}/.." && rm -f "${zip_name}" && zip -qr "${zip_path}" "${name}")
  sha="$(sha256sum "${zip_path}" | cut -d' ' -f1)"
  size="$(stat -c%s "${zip_path}")"

  # 元数据子集（与 ps1 版输出一致；缺省字段由客户端 serde default 兜底）
  meta="$(jq '{display_name, description, type, tier, agent_compat, categories, permissions, compat, apis, channel}' "${manifest}")"

  entry="$(jq -n \
    --arg name "${name}" \
    --arg version "${version}" \
    --arg zip "dist/${zip_name}" \
    --arg sha "${sha}" \
    --argjson size "${size}" \
    --argjson meta "${meta}" \
    '$meta + {name: $name, version: $version,
      downloads: [{platform: "any", url: $zip, sha256: $sha, size: $size}]}')"

  entries="$(jq -n --argjson acc "${entries}" --argjson e "${entry}" '$acc + [$e]')"
  count=$((count + 1))
  echo "  packaged ${name}@${version} -> ${zip_name} (sha256 ${sha:0:12}…)"
done

# 按 name 排序，保证 registry 内容稳定
entries="$(jq 'sort_by(.name)' <<<"${entries}")"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --argjson skills "${entries}" \
  --arg now "${now}" \
  --arg min_client "0.1.0" \
  '{version: "0.2.0", min_client_version: $min_client, updated_at: $now, skills: $skills}' \
  > "${OUT_DIR}/registry.json"

echo "registry: ${count} skills -> ${OUT_DIR}/registry.json"
