#!/bin/bash
# Lobster Distill - Pack, Encrypt, Upload / 龙虾蒸馏 - 打包、加密、上传
# Usage / 用法: bash share.sh <path> [description]
# <path> can be a file or directory / <path> 可以是文件或目录

set -e

SRC="$1"
DESC="${2:-Skill package}"
TMPDIR=$(mktemp -d)

if [ -z "$SRC" ]; then
    echo "Usage / 用法: bash share.sh <file-or-dir> [description]"
    echo "  <file-or-dir>: skill directory or single file / 技能目录或单个文件"
    echo "  [description]: brief description / 简要描述"
    exit 1
fi

# Generate random password (24 chars) / 生成随机密码（24 字符）
PASSWORD=$(openssl rand -base64 18)

# Determine name / 确定名称
BASENAME=$(basename "$SRC")

if [ -d "$SRC" ]; then
    # Directory: tar it up / 目录：打包为 tar.gz
    PACKED="$TMPDIR/${BASENAME}.tar.gz"
    tar czf "$PACKED" -C "$SRC" .
    FILETYPE="tar.gz"
    echo "[+] Packed directory / 已打包目录: $SRC -> $PACKED"
else
    # Single file: copy as-is / 单文件：直接复制
    PACKED="$TMPDIR/$BASENAME"
    cp "$SRC" "$PACKED"
    FILETYPE="file"
    echo "[+] Using file / 使用文件: $SRC"
fi

# Encrypt with AES-256-CBC + PBKDF2 / 使用 AES-256-CBC + PBKDF2 加密
ENCRYPTED="$TMPDIR/${BASENAME}.enc"
openssl enc -aes-256-cbc -pbkdf2 -salt -in "$PACKED" -out "$ENCRYPTED" -k "$PASSWORD"
echo "[+] Encrypted with AES-256-CBC / 已加密"

# Get file size / 获取文件大小
SIZE=$(du -h "$ENCRYPTED" | cut -f1)

# Upload: try c2cprotocol.org/share first (10min), fallback to litterbox (24h)
# 上传：优先使用 c2cprotocol.org/share（10分钟），失败则回退到 litterbox（24小时）
EXPIRY="10 minutes"
echo "[+] Uploading to c2cprotocol.org/share / 正在上传到 c2cprotocol.org/share..."
RESPONSE=$(curl -s -f -F "file=@$ENCRYPTED" https://c2cprotocol.org/share/upload 2>/dev/null)
URL=$(echo "$RESPONSE" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$URL" ]; then
    echo "[+] Uploaded to C2C Share / 已上传到 C2C Share: $URL"
else
    echo "[!] C2C Share failed, falling back to litterbox / C2C Share 失败，回退到 litterbox..."
    EXPIRY="24 hours"
    URL=$(curl -s -F "reqtype=fileupload" -F "time=24h" -F "fileToUpload=@$ENCRYPTED" https://litterbox.catbox.moe/resources/internals/api.php)
    if [ -z "$URL" ] || echo "$URL" | grep -qi "error"; then
        echo "[-] Both uploads failed / 两个上传都失败: $URL"
        rm -rf "$TMPDIR"
        exit 1
    fi
    echo "[+] Uploaded to litterbox / 已上传到 litterbox: $URL"
fi

# Clean up temp dir only (created by mktemp above, contains only our packed/encrypted copies)
# 仅清理临时目录（由上方 mktemp 创建，只包含我们的打包/加密副本）
rm -rf "$TMPDIR"

# ============================================================
# Single message with two clearly separated sections
# 一条消息，两个清晰分隔的部分
# ============================================================
echo ""
echo "═══ 📋 FOR ADMIN / 管理员请读 ═══"
echo ""
echo "📦 Skill / 技能: $DESC"
echo "📁 Source / 来源: $BASENAME ($FILETYPE, $SIZE encrypted / 已加密)"
echo "⏰ Expires in $EXPIRY / ${EXPIRY}后过期"
echo ""
echo "👉 Please forward this entire message to the target agent."
echo "👉 请将此完整消息转发给目标智能体。"
echo ""
echo "The target agent will read the section below."
echo "目标智能体会读取下方内容。"
echo ""
echo "═══ 🦞 FOR TARGET AGENT / 目标智能体请读 ═══"
echo ""

if [ "$FILETYPE" = "tar.gz" ]; then
cat << NOTES
🦞 Skill Transfer Package / 技能传授包

**Skill / 技能:** $DESC
**File / 文件:** ${BASENAME}.tar.gz (encrypted / 已加密)
**Size / 大小:** $SIZE

**Download & Install Steps / 下载与安装步骤：**

\`\`\`bash
# 1. Download encrypted file / 下载加密文件
curl -o /tmp/${BASENAME}.enc "$URL"

# 2. Decrypt / 解密
openssl enc -aes-256-cbc -d -pbkdf2 -in /tmp/${BASENAME}.enc -out /tmp/${BASENAME}.tar.gz -k "$PASSWORD"

# 3. Extract to skills directory / 解压到技能目录
mkdir -p skills/${BASENAME}
tar xzf /tmp/${BASENAME}.tar.gz -C skills/${BASENAME}/

# 4. Read the skill documentation / 阅读技能文档
cat skills/${BASENAME}/SKILL.md

# 5. Clean up temp files / 清理临时文件
rm -f /tmp/${BASENAME}.enc /tmp/${BASENAME}.tar.gz
\`\`\`

⏰ Link expires in $EXPIRY, download ASAP. / 链接${EXPIRY}后过期，请尽快下载。
NOTES
else
cat << NOTES
🦞 Skill Transfer Package / 技能传授包

**Skill / 技能:** $DESC
**File / 文件:** ${BASENAME} (encrypted / 已加密)
**Size / 大小:** $SIZE

**Download & Install Steps / 下载与安装步骤：**

\`\`\`bash
# 1. Download encrypted file / 下载加密文件
curl -o /tmp/${BASENAME}.enc "$URL"

# 2. Decrypt / 解密
openssl enc -aes-256-cbc -d -pbkdf2 -in /tmp/${BASENAME}.enc -out /tmp/${BASENAME} -k "$PASSWORD"

# 3. Read the content / 阅读内容
cat /tmp/${BASENAME}

# 4. Clean up / 清理
rm -f /tmp/${BASENAME}.enc
\`\`\`

⏰ Link expires in $EXPIRY, download ASAP. / 链接${EXPIRY}后过期，请尽快下载。
NOTES
fi
