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
  tier="$(jq -r '.tier // "free"' "${manifest}")"
  if [ -z "${name}" ] || [ "${name}" = "null" ] || [ -z "${version}" ] || [ "${version}" = "null" ]; then
    echo "WARN: skip ${manifest}: missing name/version" >&2
    continue
  fi

  # 元数据子集（与 ps1 版输出一致；缺省字段由客户端 serde default 兜底）
  meta="$(jq '{display_name, description, type, tier, agent_compat, categories, permissions, compat, apis, channel}' "${manifest}")"

  if [ "${tier}" = "premium" ]; then
    # 付费技能：dist 只放 AES 加密包（license-tool pack 预先产出到技能目录 pkg/ 下），
    # 明文源码绝不打包进公开 dist；无加密包则跳过（等运营补包）
    enc_src="$(find "${skill_dir}/pkg" -maxdepth 1 -name '*.enc' -type f 2>/dev/null | head -n 1)"
    if [ -z "${enc_src}" ]; then
      echo "WARN: skip ${name}@${version}: premium skill missing pkg/*.enc (run license-tool pack first)" >&2
      continue
    fi
    zip_name="${name}-${version}.zip.enc"
    zip_path="${out_abs}/dist/${zip_name}"
    cp -f "${enc_src}" "${zip_path}"
    sha="$(sha256sum "${zip_path}" | cut -d' ' -f1)"
    size="$(stat -c%s "${zip_path}")"
    echo "  packaged ${name}@${version} [premium, encrypted] -> ${zip_name} (sha256 ${sha:0:12}…)"
  else
    zip_name="${name}-${version}.zip"
    zip_path="${out_abs}/dist/${zip_name}"
    # zip 根 = 技能目录内容（SKILL.toml/SKILL.md/manifest.json 均在归档根）；
    # 排除 pkg/（付费技能加密包存放目录，不进免费技能归档）
    (cd "${skill_dir}/.." && rm -f "${zip_path}" && zip -qr "${zip_path}" "${name}" -x "${name}/pkg/*")
    sha="$(sha256sum "${zip_path}" | cut -d' ' -f1)"
    size="$(stat -c%s "${zip_path}")"
    echo "  packaged ${name}@${version} -> ${zip_name} (sha256 ${sha:0:12}…)"
  fi

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
