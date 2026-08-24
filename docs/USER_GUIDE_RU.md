# VapourWiki — справочник пресетов Audion VS Engine (RU)

Полный русский справочник по 22 пресетам в 4 палитрах. В начале — **decision tree** «какой пресет тянуть для конкретной задачи». Дальше — детальное описание каждого пресета: что делает, под какой материал, ключевые параметры, рекомендуемый энкодер.

> Английский эквивалент — docstring внутри каждого `.vpy` файла в `system_core/presets/<palette>/`. Этот документ — русское дополнение для быстрой навигации.

---

## Перед началом: доустановить движок

В раздачу не входят VapourSynth и его плагины — около семидесяти
модулей, у каждого своя лицензия. Программа ставит
их сама, с сайтов авторов.

Пока это не сделано, ни один пресет из описанных ниже не запустится.

Запустите `builder_main.cmd` и выберите по порядку: `VAPOURSYNTH` (10),
`VS PLUGINS` (11). Порядок
важен: плагинам нужен уже установленный движок.

## Decision tree — какой пресет под какую задачу

Читать сверху вниз: первый совпавший случай — ваш пресет.

| Симптом материала | Пресет | Палитра |
|---|---|---|
| Чересстрочный legacy (DV, HDV, оцифровка VHS, broadcast TS) | **`qtgmc_deinterlace`** | restoration |
| NTSC 29.97 fps с 3:2 pulldown (телекино, плёнка → видео) | **`tivtc_ivtc`** | restoration |
| Шум от высокого ISO, ночная съёмка, сохранить детали | **`mvtools_mcdegrain`** | restoration |
| Радуга / dot crawl на VHS-rip / композитном захвате | **`derainbow_decross`** | restoration |
| Пережатый H.264/MPEG (YouTube-rip, WhatsApp, SD broadcast) | **`deblock_h264_artefacts`** | restoration |
| Дымка / низкая чёткость / нужно «приподнять» картинку | **`dehaze_local_contrast`** | restoration |
| Цифровой шум только в тенях ("ночная" цифровая съёмка) | **`shadow_denoise_sota`** ⭐ | precision |
| Лёгкий равномерный шум, hardware-agnostic (без CUDA/OpenCL) | `mild_denoise` | precision |
| Только хроматический шум (грязный синий канал) | `chroma_cleanup` | precision |
| Бандинг в градиентах (небо, стена) | `deband_safe` или `deband_fine_grain` | precision |
| Хочу один пресет «всё сразу» под filmic-материал | **`filmic_rebuild`** ⭐ | precision |
| Подготовка к colour grading в DaVinci | `pregrade_prep` | precision |
| Чистый архивный мастер без зерна | `archive_clean` | precision |
| Тонкий filmic look, безопасный default | `cinematic` | film_looks |
| Конкретный 35mm Kodak (250D / 500T / 50D) | `film_35mm` | film_looks |
| 16mm органичный, поднятые тени | `film_16mm` | film_looks |
| Super 8, выцветшие 70-е, тяжёлое зерно | `super8` | film_looks |
| High contrast desaturated (Se7en, Saving Private Ryan) | `bleach_bypass` | film_looks |
| VHS / CRT эстетика | `vhs_crt` | retro |
| 90s любительский camcorder | `camcorder_90s` | retro |

**Pipeline-сценарии** (несколько пресетов цепочкой через `apply-profile-batch` или ручной запуск):

| Сценарий | Шаги |
|---|---|
| Ночной timelapse → плёнка | `shadow_denoise_sota` → `filmic_rebuild` → `cinematic` |
| Архив VHS → отреставрированный мастер | `qtgmc_deinterlace` → `derainbow_decross` → `mvtools_mcdegrain` → `archive_clean` |
| Старый YouTube-rip → пригодный для проекта | `deblock_h264_artefacts` → `dehaze_local_contrast` → `pregrade_prep` |
| Telecined NTSC DVD → 24p мастер | `tivtc_ivtc` → `archive_clean` |
| Современный цифровой → плёночный лук | `mild_denoise` → `film_35mm` |

---

## Палитра PRECISION — технический pipeline (8 пресетов)

Меню в порядке pipeline-логики: Stage 1 (denoise) → Stage 2 (deband) → Stage 3 (compositions).

### Stage 1 — шумодав

#### `mild_denoise` — мягкий универсальный шумодав

DFTTest спектральный шумодав. Pure CPU, hardware-agnostic — работает одинаково на любом процессоре. Рекомендуется как **первый выбор** когда не известно про материал ничего конкретного: лёгкий шум, нужно немного почистить без риска.

- Параметры: `strength` = light (sigma=4.0) / medium (8.0) / strong (14.0)
- Энкодер: `h264_crf17` или `h264_crf14` для архивного качества
- Что делает в Adobe/DaVinci: только Temporal NR / Noise Reduction, грубее по результату

#### `shadow_denoise_sota` ⭐ — флагман шумодава теней

BM3D с float32-конвейером + smooth luma-mask «только тени». Шум давится **только** в зонах ниже `shadow_threshold`, остальная картинка не трогается. Хрома плоскости денойзятся всегда (хроматический шум одинаково уродлив везде). Опциональный возврат микрозерна `grain_back` чтобы тени не выглядели «пластиковыми».

- Параметры: `sigma=2.5` (BM3D luma), `use_cuda=0/1`, `grain_back=0.6`, `shadow_threshold=0.20`, `transition=0.10`
- На NVIDIA: `--use-cuda 1` даёт 25–35% выигрыш wall-time на 4K
- Энкодер: `h264_crf17` / `prores_lt`
- Чего нет в NLE: zone-targeted denoise с smooth blend без дешёвого «threshold mask»

#### `chroma_cleanup` — очистка только хромы

DFTTest на planes=[1,2]. Luma не трогается. Применяется когда «грязный синий канал» (типичная проблема старых компактных камер, низкобитных AVCHD).

- Параметры: `strength` = light / medium / strong
- Энкодер: `h264_crf17`
- Чего нет в NLE: чистый chroma-only DFTTest без luma-побочки

### Stage 2 — дебанд

#### `deband_safe` — безопасный дебанд

neo_f3kdb с лёгкими настройками, без зерна. Убирает бандинг в градиентах (небо, стена, ночное освещение) без потери резкости.

- Параметры: `range=15`, `y=64`, `cb=64`, `cr=64`
- Энкодер: `h264_crf17` / `h265_crf17`

#### `deband_fine_grain` — дебанд + восстановление тонкого зерна

Тот же neo_f3kdb + AddGrain. После дебанда добавляется лёгкое монотонное зерно — исключает «слишком чистую» картинку (характерное свойство дешёвой компрессии).

- Параметры: `range=15`, `grain_var=1.5`
- Энкодер: `prores_lt` (для последующего грейдинга)

### Stage 3 — композиции

#### `filmic_rebuild` ⭐ — флагман композиций

Полная цепочка: BM3D denoise → neo_f3kdb deband → 3-zone luma grain (тени / midtones / highlights). Зерно зональное — больше в тенях (как настоящая киноплёнка), меньше в highlights. Рекомендуется как «один пресет на всё» для filmic-материала.

- Параметры: `sigma=2.0`, `use_cuda=0/1`, `deband_range=14`, `grain_shadow=1.5`, `grain_mid=0.9`, `grain_high=0.4`, `shadow_threshold=0.30`, `high_threshold=0.65`
- Энкодер: `prores_lt` / `h265_crf17`

#### `archive_clean` — нейтральный архивный мастер

DFTTest + neo_f3kdb. **Без зерна.** Цель — максимально чистая «плоская» картинка для архивирования. Не использовать если планируется грейдинг (он лучше работает на материале с зерном).

- Параметры: `denoise=medium`, `range=15`
- Энкодер: `prores_422hq` / `prores_422hq_mxf`

#### `pregrade_prep` — подготовка под DaVinci

Минимальное воздействие: только лёгкий DFTTest. Без дебанда, без зерна. Цель — отдать в Resolve самый чистый источник, чтобы колорист не работал поверх артефактов компрессии.

- Параметры: `strength=light`
- Энкодер: `prores_lt_mxf` (для round-trip с Adobe / Avid)

---

## Палитра FILM_LOOKS — эмуляции киноплёнки (5 пресетов)

Каждый look использует общую библиотеку `audion_lib` (MTF-софтенинг, halation bloom, zone grain, gamma curve, black-lift, desaturation).

### `cinematic` — универсальный subtle filmic

Безопасный default. Лёгкий MTF softening + halation + микрозерно. Не привязан к конкретной плёнке. Работает на любом современном digital-материале.

- Параметры: `intensity=1.0` (диапазон 0..2)
- Энкодер: `prores_lt` / `h264_crf17`

### `film_35mm` — Kodak 35mm с stock-вариантами

Эмуляция реальных Kodak stocks: 250D (дневной баланс), 500T (вольфрам), 50D (мелкое зерно). Каждый stock имеет свою кривую гаммы, баланс, плотность зерна.

- Параметры: `stock=250D|500T|50D`, `intensity=1.0`
- Энкодер: `prores_lt` / `prores_lt_mxf`

### `film_16mm` — органичный, более зернистый

Поднятые тени (lifted blacks), более выраженное зерно, мягче 35mm. Подходит для «documentary» / arthouse эстетики.

- Параметры: `intensity=1.0`
- Энкодер: `prores_lt`

### `super8` — самый сильный лук

Самое тяжёлое зерно, самая мягкая оптика, выцветшие 70-е. Для music video / стилизованных вставок.

- Параметры: `intensity=1.0`
- Энкодер: `h264_crf17` (зерно уже встроено, agressive compression OK)

### `bleach_bypass` — high contrast desaturated

«Se7en» / «Saving Private Ryan» лук. Высокий контраст, серебряная серость, яркие highlights. Жёсткий стилистический выбор.

- Параметры: `intensity=1.0`
- Энкодер: `prores_lt`

---

## Палитра RETRO — аналоговый характер (2 пресета)

### `vhs_crt` — VHS / CRT

Chroma bleed (горизонтальное растекание цвета), мягкая оптика, аналоговый шум. Эмуляция воспроизведения с VHS-кассеты на CRT-телевизоре.

- Параметры: `intensity=1.2`
- Энкодер: `h264_crf17`

### `camcorder_90s` — любительский camcorder

Мягче VHS, лёгкая переэкспозиция, минимальный chroma bleed. Эстетика домашних видео 90-х.

- Параметры: `intensity=1.0`
- Энкодер: `h264_crf17`

---

## Палитра RESTORATION — суперпушки (7 пресетов, Phase 18.B + NNEDI3 2x)

То, чего **нет или плохо реализовано** в Adobe Premiere / DaVinci Resolve.

### `qtgmc_deinterlace` — эталонный деинтерлейс

havsfunc.QTGMC (NNEDI3 + MVTools motion estimation). Реконструирует прогрессивные кадры из чересстрочного источника через neural network upscaling каждого поля + motion-compensated temporal smoothing. **Лучше любого NLE out-of-the-box.**

- Параметры: `field_order=tff|bff`, `qtgmc-preset=Faster|Fast|Medium|Slow|Slower|Placebo`, `output_fps=single|double`
- Когда брать: DV, HDV, оцифровка VHS, broadcast TS, оцифровка S-VHS / U-matic
- Энкодер: `prores_lt` (для последующей работы) или `h264_crf17` (если final master)

### `tivtc_ivtc` — обратный telecine

TIVTC.TFM (field matching) + TIVTC.TDecimate (drop duplicate). Reference-quality 3:2 pulldown removal: NTSC 29.97i → 23.976p. Возвращает оригинальный плёночный 24p мастер из telecined источника.

- Параметры: `pp=6` (TFM post-processor), `cycle=5`, `rdrop=1` (стандартный NTSC паттерн)
- Когда брать: NTSC DVD, broadcast prints, digitized film transfers
- Энкодер: `prores_422` / `prores_422hq_mxf`

### `mvtools_mcdegrain` — motion-compensated denoise

MVTools motion estimation → MDeGrain temporal averaging вдоль motion vectors. **Убирает шум БЕЗ потери детализации** — то что Topaz Video Enhance AI и Neat Video делают внутри. DaVinci Temporal NR — coarse implementation того же; здесь reference-grade.

- Параметры: `radius=2` (5-кадровое окно), `thsad=200`, `blksize=16` (HD) / `8` (4K detail)
- Когда брать: high-ISO ночная съёмка, сохранение текстуры кожи / фактуры тканей
- Энкодер: `prores_lt` / `h265_crf17`

### `derainbow_decross` — NTSC composite cleanup

MVTools-based motion-compensated chroma-only smoothing. Убирает rainbow / dot crawl / cross-color на материале с композитного захвата (VHS-rip, U-matic, BetaSP, S-Video → SDI). Luma не трогается.

- Параметры: `strength=0.6`, `blksize=16`
- Когда брать: оцифрованные VHS, цветные «пробежки» на тонких линиях, mosquito noise на чёрно-белых границах
- Энкодер: `prores_lt` / `h264_crf17`

### `deblock_h264_artefacts` — спасение пережатого

havsfunc.Deblock_QED — edge-aware deblocker для H.264 / MPEG-2 / MPEG-4. Сглаживает 8x8 границы блоков, ringing вокруг edges, mosquito noise. Edge-aware — не трогает реальную детализацию.

- Параметры: `quant1=24`, `quant2=26`, `aoffset=1`, `boffset=1`
- Когда брать: старые YouTube-rip, WhatsApp/Telegram re-encode, низкобитные SD broadcast TS
- Энкодер: `h264_crf17` (после deblock материал чище, можно re-encode на более высокий CRF)

### `dehaze_local_contrast` — clarity без halos

Luma-only local contrast через high-pass + zone-weighted MaskedMerge. Zone-mask (parabolic, peak в midtones) предотвращает выгорание highlights и crushed shadows. Цвет не сдвигается (luma-only). 16-bit math.

- Параметры: `strength=1.0`, `radius=8` (clarity) / `12-16` (haze removal)
- Когда брать: дымка, плоский low-contrast материал, нужно «оживить» картинку без destroy highlights
- Чего нет в NLE: Resolve "Dehaze" сжигает highlights и сдвигает цвет; здесь без halos
- Энкодер: `prores_lt` (handoff в colorist) или `h264_crf17` (final)

### `nnedi3_upscale_2x` — детерминированный non-ML upscale 2x

Увеличение через ZNEDI3/NNEDI3 и `nnedi3_resample`. Это Lite-вариант для чистого предсказуемого upscale без MLRT и ONNX-моделей.

- Параметры: `quality=fast|balanced|best`, `chroma=spline36|nnedi3`
- Когда брать: SD/HD архивный материал, где нужен аккуратный 2x resize без ML-галлюцинации текстуры
- Энкодер: `prores_lt` для handoff или `h264_crf14` / `h265_crf14` для final

---

## Smoke / bench статус

`install\Bench-AllPresets.{cmd,ps1}` прогоняет каждый `.vpy` пресет через `vspipe -c y4m --end <Frames-1> | ffmpeg -f null` без записи выходных файлов. Он проверяет парсинг пресета, plugin namespaces, доставку кадров и CPU/CUDA BM3D-путь, если он запрошен.

Текущие локальные references для Lite:
- CPU fallback: **22/22 PASS** при `Frames=1`, `Cuda=off` (2026-05-16).
- RTX 5070 validation: **30/30 PASS** при `Frames=1`, `Cuda=sweep` (2026-05-27). 30 строк — это 22 пресета плюс дополнительный CPU/CUDA sweep для Precision.

```cmd
system_core\powershell\pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File install\Bench-AllPresets.ps1 -ProjectRoot . -InputFile <video> -Frames 1 -Cuda sweep
```

---

## Энкодеры — мои паттерны

(Audion default workflow по результатам обсуждения 2026-04-28)

**Quality ladder** (одинаковая 14 / 17 / 21 сетка для software, NVENC, QuickSync и AMF): **14 → 17 → 21**, три различимые ступени без overlap.

| Профиль | Когда использовать |
|---|---|
| `h264_crf14` / `h265_crf14` ⭐ default | Semi-lossless архив, мастер для последующей работы. **Default Audion с 2026-04-28.** |
| `h264_crf17` / `h265_crf17` | «Почти невидимый lossy», финальный master |
| `h264_crf21` / `h265_crf21` | Web preview / proxy / превью |
| `prores_lt` ⭐ | Audion default ProRes — без keying, под grading и round-trip |
| `prores_lt_mxf` ⭐ | ProRes LT в MXF wrapper — для Adobe Premiere / Avid round-trip |
| `prores_422` | Если нужно чуть больше bitrate чем LT |
| `prores_422_mxf` | ProRes 422 в MXF wrapper для Adobe / Avid handoff |
| `prores_422hq` | Только если планируется keying |
| `prores_422hq_mxf` | HQ + MXF для broadcast / Avid finishing |
| `dnxhr_lb` / `_sq` / `_hq` / `_hqx` | Avid-style DNxHR (LB low / SQ standard / HQ high / HQX 10-bit) |
| **`h264_nvenc_q14` / `_q17` / `_q21`** | NVENC hardware-encode H.264 на NVIDIA. Снимает CPU-bottleneck с libx264 — VS-фильтрация не упирается в encode. **CQ — аналог CRF**. 8-bit yuv420p. |
| **`h265_nvenc_q14` / `_q17` / `_q21`** | NVENC hardware-encode HEVC, 10-bit p010le. Идеально для full pipeline на NVIDIA: VS-фильтрация на CPU/CUDA + encode на NVENC = ноль CPU-затыка. |
| **`h264_qsv_q14` / `_q17` / `_q21`** | Intel QuickSync H.264 для Intel iGPU batch/proxy. |
| **`h265_qsv_q14` / `_q17` / `_q21`** | Intel QuickSync HEVC, p010le где поддерживается. |
| **`h264_amf_q14` / `_q17` / `_q21`** | AMD AMF H.264 через CQP. |
| **`h265_amf_q14` / `_q17` / `_q21`** | AMD AMF HEVC, p010le output. |

**Правило**: для любой не-final обработки → `prores_lt` / `prores_lt_mxf` или DNxHR, если принимающее приложение любит DNx. Для final delivery → `h264_crf14` / `h264_crf17` (software, лучшая плотность на бит) ИЛИ hardware ladder под текущий хост (`nvenc`, `qsv`, `amf`), когда важен wall-time.

### Когда использовать hardware encode vs software

| Сценарий | Encoder |
|---|---|
| Тяжёлый VS-pipeline (filmic_rebuild, mvtools_mcdegrain) на NVIDIA | **NVENC** — CPU освобождается под VS-фильтр, общий wall-time падает на 30-50% |
| Финальный delivery где важна максимальная плотность бит | **libx264/libx265 CRF** — software encoder всё ещё чуть точнее на низких CRF |
| Intel iGPU / ноутбучный batch | **QuickSync** — хороший throughput при низкой нагрузке на CPU |
| AMD/Radeon host | **AMF** — та же 14/17/21 CQP ladder, без CPU encode bottleneck |
| Большой батч на сотни файлов | **NVENC / QSV / AMF** — экономия времени накапливается |
| Нет рабочего hardware encoder | Только software (`h264_crf*` / `h265_crf*`) |

NVENC требует: NVIDIA driver R525+. Качество: NVENC на Ada/Blackwell (RTX 40/50) **сравнимо** с libx264 medium на одинаковом CQ; на старых поколениях (Pascal/Turing) software CRF немного выигрывает в эффективности bitrate за то же качество, но NVENC всё равно быстрее в разы.

---

## Дополнительно — полная справка

- Английская справка по каждому пресету: docstring в `system_core/presets/<palette>/<preset>.vpy`
- CLI флаги: `runtime\python.exe system_core\main.py run --help`
- Профили (cross-палитровые комбинации): `runtime\python.exe system_core\main.py list-profiles`
- Recursive batch с mirror folder structure: `apply-profile-batch --recursive`
- Проверка стека: `runtime\python.exe system_core\doctor.py`

---

**Last updated**: 2026-05-27 (Phase 18.B + NNEDI3 2x — 22 presets across 4 palettes; CPU fallback smoke `22/22 PASS`, `Frames=1`, `Cuda=off`; RTX 5070 CUDA smoke `30/30 PASS`, `Frames=1`, `Cuda=sweep`)
