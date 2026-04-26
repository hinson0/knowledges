# ── 知识库查询 ────────────────────────────────

knowledges_dir := env_var('HOME') + "/knowledges"
pdfs_dir := env_var('HOME') + "/knowledges/pdfs"

# 显示所有 PDF 文件
show:
    @echo "📁 {{knowledges_dir}}"; \
     find {{knowledges_dir}} -type f -name "*.pdf" | sort
# 将 knowledges 下所有 PDF 移动到 pdfs/当日/，同名 .md 后缀改为 .printed.md
# 不传参 = pdfs/2026-04-21/；传 2 = pdfs/2026-04-21_2/（支持同一天多次运行）
# PDF 同名冲突时自动加后缀 _2、_3...
mv suffix="":
    #!/usr/bin/env bash
    today=$(date +%Y-%m-%d)
    if [ -z "{{suffix}}" ]; then
        dest_dir="{{pdfs_dir}}/$today"
    else
        dest_dir="{{pdfs_dir}}/${today}_{{suffix}}"
    fi
    mkdir -p "$dest_dir"
    echo "📁 $dest_dir"
    count=0
    while IFS= read -r f; do
        fname=$(basename "$f")
        target="$dest_dir/$fname"
        if [ -e "$target" ]; then
            base="${fname%.pdf}"
            n=2
            while [ -e "$dest_dir/${base}_${n}.pdf" ]; do
                n=$((n + 1))
            done
            target="$dest_dir/${base}_${n}.pdf"
            echo "⚠️  $fname 冲突 → 重命名为 $(basename "$target")"
        fi
        mv "$f" "$target"
        md="${f%.pdf}.md"
        if [ -f "$md" ]; then
            mv "$md" "${md%.md}.printed.md"
            echo "✅ $(basename "$target")  +  ${fname%.pdf}.md 标记 .printed.md"
        else
            echo "✅ $(basename "$target")（未找到同名 .md）"
        fi
        count=$((count + 1))
    done < <(find "{{knowledges_dir}}" -type f -name "*.pdf")
    if [ "$count" -eq 0 ]; then
        echo "ℹ️  knowledges 下没有 PDF"
    else
        echo ""
        echo "✅ 共移动 $count 个 PDF → $dest_dir"
    fi