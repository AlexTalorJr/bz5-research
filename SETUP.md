# Repo setup — пошаговая инструкция для owner

## Owner deployment notes

- **GitHub repo URL**: https://github.com/AlexTalorJr/bz5-research (public)
- **Local clone path**: `/Users/alexandrbaiko/development/bz5-research`
- **Helper invocation**: `~/development/bz5-research/bz5-snap.sh` (или установить `BZ5_RESEARCH_DIR` env var и звать `bz5-snap` из любого места — см. шаг 5)

Эти detail'ы зафиксированы здесь чтобы будущая Claude-сессия знала
где локально лежит clone и не задавала повторные вопросы при start'е.
Только owner использует эти пути; они полезны только когда я (companion
Claude) reconstruct'ить контекст в новой сессии.

## Шаг 1: создать public репо на GitHub

Через `gh` CLI:
```bash
mkdir bz5-research
cd bz5-research
tar xzf ~/Downloads/bz5-research-scaffold.tar.gz --strip-components=1
git init
git add -A
git commit -m "Initial research scaffold (companion Claude)"
gh repo create bz5-research --public --source=. --remote=origin --push
```

Или через веб-UI:
1. github.com → New repository
2. Name: `bz5-research`
3. Public, no README (мы свой имеем)
4. Create
5. Локально:
```bash
mkdir bz5-research
cd bz5-research
tar xzf ~/Downloads/bz5-research-scaffold.tar.gz --strip-components=1
chmod +x bz5-snap.sh
git init
git branch -M main
git add -A
git commit -m "Initial research scaffold (companion Claude)"
git remote add origin https://github.com/<your-username>/bz5-research.git
git push -u origin main
```

## Шаг 2: раздать права

### Друг 2 — Collaborator с write access

В GitHub settings нового репо:
1. Settings → Collaborators → Add people
2. Найти GitHub username Друга 2
3. Permission: **Write** (это позволит ему commit'ить sweep results)
4. Send invitation — он подтвердит

**Почему Write, не Maintain или Admin**:
- Write позволяет commit'ить и push'ить в main
- Не даёт удалять repo, менять settings, или давать кому-то ещё доступ
- Достаточно для всего что Другу 2 нужно

### Companion Claude (я) — без direct access

Я **не имею** аккаунта на GitHub и не должен иметь access token. Workflow:
- Чтение: я clone'ю через **public HTTPS** (потому что repo public, auth не нужен)
- Запись: я генерирую `.patch` файлы, ты их применяешь через `git am` и push'ишь

### Recon Claude / любые будущие участники

Не давать write access. Если им нужно прочитать что-то — repo public, читают как все.

## Шаг 3: пригласить Друга 2

Отправь Другу 2 (это сообщение в твоей чат-сессии с ним):

> Создал public repo `bz5-research` для investigation workflow. URL: https://github.com/<username>/bz5-research
> Пригласил тебя как collaborator с write access — accept в email или в Notifications на github.com.
> Структура и инструкции в README.md. Жду твоего LGTM по двум query вопросам из последнего сообщения (роль bridge Claude и schema sweep_results).

## Шаг 4: установить helper script

```bash
# Где-нибудь в PATH, например ~/.local/bin
mkdir -p ~/.local/bin
cp ~/bz5-research/bz5-snap.sh ~/.local/bin/bz5-snap
chmod +x ~/.local/bin/bz5-snap
# Убедись что ~/.local/bin в PATH:
echo $PATH | grep -q "$HOME/.local/bin" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Если не хочется PATH-fiddling, оставь script в репо и зови `./bz5-snap.sh`.

## Шаг 5: установить BZ5_RESEARCH_DIR (опционально)

Чтобы зови `bz5-snap warm` из любой папки:
```bash
echo 'export BZ5_RESEARCH_DIR="$HOME/bz5-research"' >> ~/.zshrc
source ~/.zshrc
```

## Workflow per session

### В начале сессии
```bash
bz5-snap warm     # → /tmp/bz5-snap-warm.tar.gz (~50-200 KB)
# Drag-drop этот файл в Claude чат
```

### В конце сессии
Я отдам patch файл `cycle-NNN.patch` через chat artifacts. Ты:
```bash
cd ~/bz5-research
# Скачай patch (artifact становится файлом в ~/Downloads/)
git am < ~/Downloads/cycle-NNN.patch
# (или: git apply --3way если конфликт с push'ами Друга 2)
git push
```

### Если нужен старый cycle
```bash
bz5-snap cycle 7
# → /tmp/bz5-snap-cycle-007.tar.gz
# Drag в чат
```

### Если что-то крупное и нужен полный snapshot
```bash
bz5-snap full
# → /tmp/bz5-snap-full.tar.gz
```

## Правила гигиены

1. **Raw data > 100 KB**: жми gzip'ом. Друг 2 commit'ит `.csv.gz`, я decompress при чтении.
2. **Один cycle = один commit** (со стороны Друга 2 — он commit'ит hypothesis я cycle-NNN.patch'ем; results он commit'ит отдельным push'ем когда execute'нет).
3. **Конфликты**: они возможны если я работаю над cycle NNN параллельно с тем что Друг 2 push'ит cycle (NNN-1) results. Решается `git am --3way` или просто pull → re-apply patch.
4. **Не складывать в repo секреты**: client_token'ы, admin token'ы, raw БД dump'ы.

## Если что-то пошло не так

- **Patch не применяется**: pull сначала, потом `git am --3way`. Если совсем плохо — открой patch файл, скопируй содержимое руками, commit обычным `git commit`.
- **Я не вижу новых commits Друга 2**: сделай `bz5-snap warm` заново, он pull'ит автоматически.
- **Helper script ошибается**: `bash -x bz5-snap.sh warm` для verbose output.
