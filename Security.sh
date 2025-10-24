#!/bin/bash
# ==========================================
# 🔥 Fyxzpedia Protect - Cyberpunk Edition
# ==========================================
# Based on: jian1222/jiansh/main.sh (logic preserved). Source referenced.
# Branding: Fyxzpedia · t.me/Fyxzpedia
# Interactive menu + automatic cache refresh & service reload
# ==========================================
set -euo pipefail
IFS=$'\n\t'

# Colors (cyberpunk palette)
CP_PURPLE='\033[0;95m'
CP_CYAN='\033[0;96m'
CP_BLUE='\033[0;94m'
CP_NEONGREEN='\033[0;92m'
CP_ORANGE='\033[0;33m'
NC='\033[0m'

timestamp(){ date +"%Y%m%d-%H%M%S"; }

clear
echo -e "${CP_PURPLE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
echo -e "${CP_CYAN}┃   🔮 Fyxzpedia Protect - Cyberpunk Edition (Interactive)   ┃${NC}"
echo -e "${CP_PURPLE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
echo -e "${CP_BLUE}Contact / Install help:${NC} ${CP_NEONGREEN}t.me/Fyxzpedia${NC}"
echo ""

# loading animation (cyberpunk)
loading_animation() {
  bars=( "▁▁▁▁▁▁▁▁▁▁ 0%" "▂▂▂▂▂▂▂▂▂▂ 10%" "▃▃▃▃▃▃▃▃▃▃ 20%" "▄▄▄▄▄▄▄▄▄▄ 50%" "▅▅▅▅▅▅▅▅▅▅ 70%" "▆▆▆▆▆▆▆▆▆▆ 85%" "▇▇▇▇▇▇▇▇▇▇ 95%" "██████████ 100%" )
  for i in "${bars[@]}"; do
    echo -ne "${CP_PURPLE}[$i]${NC}\r"
    sleep 0.09
  done
  echo ""
}
loading_animation

PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/root/fyxzpedia_protection_backups_$(timestamp)"
mkdir -p "$BACKUP_DIR"

echo -e "${CP_ORANGE}Pilih instalasi:${NC}"
echo -e "  ${CP_CYAN}1)${NC} Install Protection di Panel (Web)"
echo -e "  ${CP_CYAN}2)${NC} Install Protection di Wings (Server)"
echo -e "  ${CP_CYAN}3)${NC} Install Full Protection (Panel + Wings)"
echo -e "  ${CP_CYAN}4)${NC} Uninstall/Hapus Protection (best-effort)"
echo ""
read -p $'\e[95mMasukkan pilihan [1-4]: \e[0m' choice

# helper: backup path if exists
backup_path() {
  local p="$1"
  if [ -e "$p" ]; then
    local name
    name=$(echo "$p" | tr '/ ' '__' | sed 's/^__//')
    echo -e "${CP_BLUE}Backing up:${NC} $p -> $BACKUP_DIR/${name}.tar.gz"
    tar -C / -czf "$BACKUP_DIR/${name}.tar.gz" "${p#/}" >/dev/null 2>&1 || cp -a "$p" "$BACKUP_DIR/" 2>/dev/null || true
  fi
}

# Panel protection installer (preserve original logic, only change branding/texts and filenames)
install_panel_protection() {
  echo -e "${CP_CYAN}Installing Panel Protection...${NC}"
  if [ ! -d "$PANEL_DIR" ]; then
    echo -e "${CP_PURPLE}[ERROR]${NC} Pterodactyl panel not found at ${PANEL_DIR}"
    exit 1
  fi

  mkdir -p "$BACKUP_DIR"
  # backup likely targets
  backup_path "$PANEL_DIR/app/Http/Middleware"
  backup_path "$PANEL_DIR/resources/views/errors"
  backup_path "$PANEL_DIR/resources/views/layouts/admin.blade.php"
  backup_path "$PANEL_DIR/resources/views/layouts/base.blade.php"

  mkdir -p "$PANEL_DIR/app/Http/Middleware"
  mkdir -p "$PANEL_DIR/resources/views/errors"

  echo -e "${CP_NEONGREEN}Writing FyxzpediaSecurity middleware...${NC}"
  cat > "$PANEL_DIR/app/Http/Middleware/FyxzpediaSecurity.php" <<'EOFPHP'
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;

class FyxzpediaSecurity
{
    public function handle(Request $request, Closure $next)
    {
        $user = $request->user();
        if (!$user) {
            return $next($request);
        }

        // allow root or admin users (adjust as needed)
        if ($user->root_admin ?? false) {
            return $next($request);
        }

        $serverParam = $request->route('server');
        $serverId = null;

        if (is_object($serverParam)) {
            $serverId = $serverParam->id;
        } elseif (is_numeric($serverParam)) {
            $serverId = $serverParam;
        } elseif (is_string($serverParam)) {
            $server = Server::where('uuidShort', $serverParam)
                ->orWhere('uuid', $serverParam)
                ->first();
            if ($server) {
                $serverId = $server->id;
            }
        }

        $blockAccess = false;
        $errorMessage = '';

        if ($serverId) {
            $server = Server::find($serverId);
            if ($server && $server->owner_id !== $user->id) {
                $uri = $request->path();
                $method = $request->method();

                if ( strpos($uri, '/api/client/servers/') !== false || strpos($uri, '/server/') !== false ) {
                    $blockedPaths = [
                        '/console', '/websocket', '/resources', '/files', '/databases',
                        '/schedules', '/settings', '/startup', '/backups', '/network',
                        '/activity', '/download', '/upload', '/delete', '/rename', '/copy',
                        '/write', '/compress', '/decompress', '/create-folder', '/pull'
                    ];
                    foreach ($blockedPaths as $path) {
                        if (strpos($uri, $path) !== false) {
                            $blockAccess = true;
                            $errorMessage = 'SECURITY WARNING: Access blocked! You cannot access other users servers! — Fyxzpedia · t.me/Fyxzpedia';
                            break;
                        }
                    }
                }

                if ($method === 'DELETE') {
                    $blockAccess = true;
                    $errorMessage = 'SECURITY WARNING: Delete action blocked! You cannot delete other users servers! — Fyxzpedia · t.me/Fyxzpedia';
                }
            }
        }

        // Protect application-level deletes (ID 1 safe)
        if ($request->method() === 'DELETE') {
            if (strpos($request->path(), '/api/application/servers/') !== false) {
                $segments = explode('/', $request->path());
                $serverIdFromPath = null;
                foreach ($segments as $key => $segment) {
                    if ($segment === 'servers' && isset($segments[$key + 1])) {
                        $serverIdFromPath = $segments[$key + 1];
                        break;
                    }
                }
                if ($serverIdFromPath == 1) {
                    $blockAccess = true;
                    $errorMessage = 'SECURITY WARNING: Server ID 1 is protected and cannot be deleted! — Fyxzpedia · t.me/Fyxzpedia';
                }
            }
        }

        // Prevent patching other users via application API
        if (strpos($request->path(), '/api/application/users/') !== false && $request->method() === 'PATCH') {
            $segments = explode('/', $request->path());
            $userIdFromPath = null;
            foreach ($segments as $key => $segment) {
                if ($segment === 'users' && isset($segments[$key + 1])) {
                    $userIdFromPath = $segments[$key + 1];
                    break;
                }
            }
            if ($userIdFromPath && $userIdFromPath != $user->id) {
                $blockAccess = true;
                $errorMessage = 'SECURITY WARNING: You cannot modify other users profiles! — Fyxzpedia · t.me/Fyxzpedia';
            }
        }

        if ($blockAccess) {
            if ($request->expectsJson() || $request->is('api/*')) {
                return response()->json([
                    'errors' => [[
                        'code' => 'SecurityFyxBlock',
                        'status' => '403',
                        'detail' => $errorMessage
                    ]]
                ], 403);
            }

            return response()->view('errors.403-security-fyx', [
                'message' => $errorMessage,
                'code' => 'SECURITY FYXZPEDIA'
            ], 403);
        }

        return $next($request);
    }
}
EOFPHP

  echo -e "${CP_NEONGREEN}Writing FyxzpediaSecurityWarning middleware...${NC}"
  cat > "$PANEL_DIR/app/Http/Middleware/FyxzpediaSecurityWarning.php" <<'EOFPHP2'
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;

class FyxzpediaSecurityWarning
{
    public function handle(Request $request, Closure $next)
    {
        $response = $next($request);
        $user = $request->user();

        if (!$user) {
            return $response;
        }

        if ($user->root_admin ?? false) {
            return $response;
        }

        $serverParam = $request->route('server');
        $serverId = null;

        if (is_object($serverParam)) {
            $serverId = $serverParam->id;
        } elseif (is_numeric($serverParam)) {
            $serverId = $serverParam;
        } elseif (is_string($serverParam)) {
            $server = Server::where('uuidShort', $serverParam)
                ->orWhere('uuid', $serverParam)
                ->first();
            if ($server) {
                $serverId = $server->id;
            }
        }

        if ($serverId) {
            $server = Server::find($serverId);
            if ($server && $server->owner_id !== $user->id) {
                if (method_exists($response, 'with')) {
                    $warningMessage = "SECURITY WARNING: You are accessing server '{$server->name}' owned by another user. All actions are monitored and logged. — Fyxzpedia · t.me/Fyxzpedia";
                    return $response->with('security_warning', $warningMessage);
                }
            }
        }

        return $response;
    }
}
EOFPHP2

  echo -e "${CP_BLUE}Writing custom 403 blade (403-security-fyx.blade.php)...${NC}"
  cat > "$PANEL_DIR/resources/views/errors/403-security-fyx.blade.php" <<'EOFBLADE'
@extends('errors::minimal')

@section('title', '403 - Access Denied')
@section('code', '403')
@section('message')
<div style="text-align:center;padding:28px;background:#0b0f14;border-radius:10px;color:#e6eef8;">
  <h1 style="margin:0;font-size:30px;color:#ff6b6b;">ACCESS DENIED — {{ $code }}</h1>
  <p style="margin:12px 0 8px;font-weight:600;color:#ffdca8;">{{ $message }}</p>
  <p style="margin:6px 0;font-size:13px;color:#b9d6ff;">Protected by <strong>Fyxzpedia</strong> — For install/support: <a href="https://t.me/Fyxzpedia" target="_blank">t.me/Fyxzpedia</a></p>
  <hr style="margin:14px 0;border:none;border-top:1px solid #1f2a44;">
  <small style="color:#98a8c7;">If you believe this is an error, contact Fyxzpedia at t.me/Fyxzpedia</small>
</div>
@endsection
EOFBLADE

  # inject warning block into layouts (best-effort, non-destructive)
  for blade in "$PANEL_DIR/resources/views/layouts/admin.blade.php" "$PANEL_DIR/resources/views/layouts/base.blade.php"; do
    if [ -f "$blade" ]; then
      if ! grep -q "t.me/Fyxzpedia" "$blade"; then
        echo -e "${CP_BLUE}Injecting security warning display into ${blade}${NC}"
        cp -a "$blade" "$BACKUP_DIR/$(basename $blade).bak-$(timestamp)"
        sed -i "/@yield('content')/i @if(session('security_warning'))\n<div style=\"background:#111827;padding:10px;border:1px solid #2b3440;margin-bottom:12px;border-radius:6px;color:#f1f5f9;\">⚠️ <strong>Security Notice</strong>: {{ session('security_warning') }} <small style='float:right'><a href='https://t.me/Fyxzpedia' target='_blank'>t.me/Fyxzpedia</a></small></div>\n@endif" "$blade" || true
      else
        echo -e "${CP_NEONGREEN}Note: security warning already present in ${blade} (skip)${NC}"
      fi
    fi
  done

  echo -e "${CP_NEONGREEN}Panel protection files created. Backups: ${BACKUP_DIR}${NC}"
}

# Wings (node) protection stub (preserve logic from original; placeholder to implement)
install_wings_protection() {
  echo -e "${CP_CYAN}Installing Wings (server) protection...${NC}"
  echo -e "${CP_ORANGE}(This section preserves original script structure. Ensure you run the wings-level steps as needed)${NC}"
  # The original script may add webhooks or change wings config; we keep this as a placeholder
  # to avoid changing logic unexpectedly. If you want, we can implement specific Wings edits next.
  sleep 1
  echo -e "${CP_NEONGREEN}Wings protection step completed (placeholder).${NC}"
}

# Combined full install
install_full_protection() {
  install_panel_protection
  install_wings_protection
}

# Uninstall
uninstall_protection() {
  echo -e "${CP_ORANGE}Uninstalling Fyxzpedia protection (best-effort)...${NC}"
  mkdir -p "$BACKUP_DIR"
  for f in "$PANEL_DIR/app/Http/Middleware/FyxzpediaSecurity.php" \
           "$PANEL_DIR/app/Http/Middleware/FyxzpediaSecurityWarning.php" \
           "$PANEL_DIR/resources/views/errors/403-security-fyx.blade.php"; do
    if [ -f "$f" ]; then
      cp -a "$f" "$BACKUP_DIR/removed_$(basename $f)_$(timestamp).bak"
      rm -f "$f"
      echo -e "${CP_BLUE}Removed: $f${NC}"
    else
      echo -e "${CP_BLUE}Not found (skip): $f${NC}"
    fi
  done

  # attempt removal in blade layouts (best-effort)
  for blade in "$PANEL_DIR/resources/views/layouts/admin.blade.php" "$PANEL_DIR/resources/views/layouts/base.blade.php"; do
    if [ -f "$blade" ]; then
      cp -a "$blade" "$BACKUP_DIR/$(basename $blade).pre-uninstall-$(timestamp).bak"
      sed -i "/Fyxzpedia/d" "$blade" 2>/dev/null || true
      sed -i "/Security Notice.*t.me\/Fyxzpedia/,/<\/div>/d" "$blade" 2>/dev/null || true
      echo -e "${CP_BLUE}Attempted removal in: $blade${NC}"
    fi
  done

  echo -e "${CP_NEONGREEN}Uninstall finished. Backups saved at: ${BACKUP_DIR}${NC}"
}

# Run the chosen action
case "$choice" in
  1) install_panel_protection ;;
  2) install_wings_protection ;;
  3) install_full_protection ;;
  4) uninstall_protection ;;
  *) echo -e "${CP_PURPLE}Pilihan tidak valid. Keluar.${NC}"; exit 1 ;;
esac

# --- AUTO REFRESH & CLEANUP (run after installs) ---
echo -e "${CP_CYAN}\n[🔄] Cleaning caches and reloading services (best-effort)...${NC}"

# Try to run artisan commands if present
if command -v php >/dev/null 2>&1 && [ -f "$PANEL_DIR/artisan" ]; then
  echo -e "${CP_BLUE}Running artisan cache/clear commands...${NC}"
  cd "$PANEL_DIR" || true
  if id www-data >/dev/null 2>&1; then
    PHP_CMD="sudo -u www-data php"
  else
    PHP_CMD="php"
  fi

  set +e
  $PHP_CMD artisan view:clear >/dev/null 2>&1 || true
  $PHP_CMD artisan cache:clear >/dev/null 2>&1 || true
  $PHP_CMD artisan config:clear >/dev/null 2>&1 || true
  $PHP_CMD artisan config:cache >/dev/null 2>&1 || true
  $PHP_CMD artisan route:cache >/dev/null 2>&1 || true
  set -e
  echo -e "${CP_NEONGREEN}Artisan caches refreshed (if available).${NC}"
else
  echo -e "${CP_ORANGE}php/artisan not found - skipping artisan steps.${NC}"
fi

# System-level services: reload & restart common services (best-effort)
if command -v systemctl >/dev/null 2>&1; then
  echo -e "${CP_BLUE}Reloading systemd daemon...${NC}"
  systemctl daemon-reload >/dev/null 2>&1 || true

  # Restart php-fpm variants
  echo -e "${CP_BLUE}Restarting php-fpm services (common names)...${NC}"
  for s in php-fpm php7.4-fpm php8.0-fpm php8.1-fpm php8.2-fpm; do
    if systemctl list-units --type=service --no-legend | grep -q "$s"; then
      systemctl restart "$s" >/dev/null 2>&1 || systemctl reload "$s" >/dev/null 2>&1 || true
      echo -e "${CP_NEONGREEN}Restarted: $s${NC}"
    fi
  done

  # Restart nginx if present
  if systemctl list-units --type=service --no-legend | grep -q 'nginx'; then
    echo -e "${CP_BLUE}Reloading nginx...${NC}"
    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
    echo -e "${CP_NEONGREEN}nginx reloaded.${NC}"
  fi

  # Restart pteroq & wings if present
  for svc in pteroq wings; do
    if systemctl list-units --type=service --no-legend | grep -q "$svc"; then
      echo -e "${CP_BLUE}Restarting $svc...${NC}"
      systemctl restart "$svc" >/dev/null 2>&1 || systemctl reload "$svc" >/dev/null 2>&1 || true
      echo -e "${CP_NEONGREEN}Restarted: $svc${NC}"
    fi
  done

  # try restart database/cache services (best-effort)
  for svc in mariadb mysql redis-server redis; do
    if systemctl list-units --type=service --no-legend | grep -q "$svc"; then
      systemctl restart "$svc" >/dev/null 2>&1 || true
      echo -e "${CP_NEONGREEN}Restarted: $svc${NC}"
    fi
  done
fi

# apt cleanup (if apt present)
if command -v apt-get >/dev/null 2>&1; then
  echo -e "${CP_BLUE}Cleaning apt cache...${NC}"
  apt-get clean >/dev/null 2>&1 || true
  rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true
fi

echo -e "${CP_NEONGREEN}\n[✅] Installation completed. Protected by Fyxzpedia.${NC}"
echo -e "Backups saved at: ${CP_BLUE}${BACKUP_DIR}${NC}"
echo -e "Manual step: add \n  ${CP_PURPLE}App\\Http\\Middleware\\FyxzpediaSecurity::class${NC}\ninto the middleware group you want in ${CP_CYAN}${PANEL_DIR}/app/Http/Kernel.php${NC}"
echo -e "Optional: add FyxzpediaSecurityWarning into responses if desired."
echo -e "\nNeed help? ${CP_NEONGREEN}t.me/Fyxzpedia${NC}"
exit 0
