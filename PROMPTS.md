# PROMPTS.md

**Herramienta de IA utilizada:** Claude Code (Anthropic) — modelo `claude-opus-4-7`.

**Nota para el profesor:** Claude Code es la CLI oficial de Anthropic. La conversación ocurre dentro de la terminal del estudiante y **no genera un enlace público para compartir el hilo**. Por ese motivo, todos los prompts del usuario y las respuestas del asistente se registran textualmente en este archivo como evidencia del proceso (mismo criterio aplicado al Punto 1).

**Repositorio:** corresponde al **Punto 2** del examen final de Sistemas Operativos (2026-1) — desarrollo y despliegue de una aplicación FastAPI en una instancia EC2 con almacenamiento de imágenes en S3, usando systemd como gestor de servicio.

---

## Turno 1

### Prompt del usuario

> I'm Alejandro Urrego Giraldo, EIA student, working on Punto 2 of the OS final (2026-1). The exam statement is in Final.pdf — read it and focus only on point 2. Point 1 is already done in another session; PROMPTS_punto1_reference.md shows the conventions I want you to follow for this one too:
>
> - Plan-mode-first workflow. I run all AWS commands myself; you generate artifacts + docs.
> - Log every turn (prompt + response) in PROMPTS.md, same "Turno N" format.
> - Tell the teacher the AI tool is Claude Code (claude-opus-4-7) and that the CLI doesn't produce a shareable chat link, so PROMPTS.md is the evidence.
> - Screenshots go in screenshots/ with numbered kebab-case names mapped to the exam sub-items (e.g. 01-..., 02-..., one per sub-item that requires evidence). Every capture must show the system clock; AWS captures must show the IAM username. You pre-wire the placeholders in the README — I just drop the PNGs in.
> - README.md must be a self-contained summary the teacher can grade without opening anything else: header (student + AI tool + link to PROMPTS.md), one-paragraph summary, ASCII architecture diagram, file table, endpoints table, one section per sub-item (a, b, c, ...) with the relevant screenshot embedded, screenshot index table at the bottom, technical notes.

### Acciones del asistente

- Listado del directorio de trabajo del Punto 2 (solo contenía `Final.pdf`).
- Lectura de `Final.pdf` enfocado en el enunciado del Punto 2 (sub-ítems a–i).
- Lectura del `PROMPTS.md` y `README.md` del Punto 1 (`/Users/urrexx/Documents/Uni/3rdSemester/OS/Final/1/`) para extraer convenciones.
- Persistencia de memorias para futuras sesiones (perfil del usuario, conventions de workflow, log, screenshots, README, alcance del Punto 2).
- Tres preguntas al usuario sobre decisiones de diseño antes de planear:
  1. **Puerto / proxy** → respuesta: *uvicorn en :8000 directo* (recomendado).
  2. **Auth a AWS desde EC2** → respuesta: *IAM instance role* (recomendado).
  3. **Validaciones del POST** → respuesta: *las tres* (extensión + Content-Type + magic bytes).

### Respuesta del asistente

Se confirmó el alcance del Punto 2 y las convenciones del Punto 1. Se anunció entrada a *plan mode* para presentar un plan completo antes de generar archivos.

---

## Turno 2 — Plan completo (aprobado tras corrección de Turno 3)

### Acciones del asistente

1. Entró a **plan mode** (`EnterPlanMode`).
2. Escribió el plan completo en el archivo `/Users/urrexx/.claude/plans/linear-sauteeing-narwhal.md`.
3. Llamó a `ExitPlanMode` para aprobación.

### Plan presentado

#### Contexto

Desarrollo y despliegue en EC2 de una API FastAPI con:

- `POST /upload` — recibe `username` + imagen (PNG/JPG/JPEG), valida en 3 capas (extensión, content-type, magic bytes) y sube a S3 con key `users/<username>/<filename>`.
- `GET /images/{username}/{image_name}` — verifica existencia con `head_object`, devuelve presigned URL (1h) y `stored_at` desde `LastModified` de S3.
- Validación local con Swagger (no curl).
- Despliegue en EC2 (Amazon Linux 2023), uvicorn en `:8000`, IAM role para acceso a S3 (sin secretos en código).
- Archivo `fastapi-s3.service` de systemd versionado en el repo.

#### Arquitectura

```
Internet → SG :8000 → EC2 (systemd → uvicorn → FastAPI) → S3 (users/<user>/*)
                                                ↑
                                          IAM role (sin secretos)
```

#### Archivos a crear

| Archivo | Propósito |
|---|---|
| `app/main.py` | FastAPI con ambos endpoints + validaciones + boto3 a S3. |
| `app/__init__.py` | Marker de paquete. |
| `requirements.txt` | `fastapi`, `uvicorn[standard]`, `boto3`, `python-multipart`. |
| `fastapi-s3.service` | Unit systemd (Linux-only — ver Turno 3). |
| `README.md` | Documento auto-contenido para calificación. |
| `PROMPTS.md` | Este archivo. |
| `.gitignore` | Ignora `.venv/`, `__pycache__/`, `.DS_Store`, etc. |
| `screenshots/` | Carpeta para 13 capturas del estudiante. |

#### Capturas pre-cableadas

13 capturas mapeadas a los sub-ítems a–i (ver "Índice de capturas" del README para los nombres exactos): editor con código (a, d), Swagger local (b, e, f), consola S3 (c, i), consola EC2 (g), systemctl (h), Swagger público (i).

#### Riesgos identificados

- `python-multipart` requerido por FastAPI para `UploadFile`.
- `await file.seek(0)` tras leer magic bytes (si no, se sube truncado).
- IAM role debe incluir `s3:HeadObject` además de `Get/Put`.
- Bucket privado + presigned URL (no exponer el bucket).
- Olvidar abrir 8000 en el SG → timeout.

#### División de trabajo

- **Claude**: escribe todos los artefactos del repo y la documentación; actualiza `PROMPTS.md` cada turno.
- **Estudiante**: crea bucket S3 + rol IAM + EC2 + SG, edita el placeholder del bucket en `fastapi-s3.service`, ejecuta el setup en la instancia, valida en Swagger local y público, toma las 13 capturas.

---

## Turno 3

### Prompt del usuario

> Take into account that the Student is using a Mac so the .service won't work natively. Create only the code and note that to the teacher in the readme. Also register this in PROMPTS.md.

### Acciones del asistente

1. Actualizó el plan en `/Users/urrexx/.claude/plans/linear-sauteeing-narwhal.md` con una sección **"Nota sobre macOS y el `.service`"** explicando que macOS usa `launchd`, no `systemd`, y que el archivo se entrega como código versionado pero no es ejecutable en el equipo local.
2. Ajustó la "División de trabajo" para precisar que la validación local del Punto **f** se hace con `uvicorn --reload` (sin systemd), y que `systemctl enable --now` ocurre exclusivamente en EC2.
3. Llamó a `ExitPlanMode`. Plan aprobado por el usuario.

### Respuesta del asistente

Plan aprobado. El asistente procedió a crear todos los archivos del repositorio en el orden:

1. `app/__init__.py` + `app/main.py` (FastAPI con ambos endpoints, validación triple, boto3 vía IAM role, mensajes de error claros).
2. `requirements.txt` (versiones fijadas: `fastapi==0.115.0`, `uvicorn[standard]==0.30.6`, `boto3==1.35.36`, `python-multipart==0.0.12`).
3. `fastapi-s3.service` con placeholder `S3_BUCKET=<REEMPLAZAR-CON-NOMBRE-DEL-BUCKET>` para que el estudiante lo edite antes de copiarlo a la instancia.
4. `.gitignore` (`.venv/`, `__pycache__/`, `.DS_Store`, etc.).
5. `screenshots/.gitkeep` para preservar la carpeta vacía.
6. `README.md` auto-contenido: header + resumen + diagrama ASCII + tablas + sub-ítems a–i con capturas embebidas + índice de capturas + notas técnicas, incluyendo la **caja destacada explicando al profesor por qué el `.service` no se valida localmente** (macOS no corre systemd).
7. Este `PROMPTS.md` registrando los tres turnos.

### Estado del repositorio al cierre del Turno 3

```
2/
├── .gitignore
├── Final.pdf
├── PROMPTS.md
├── README.md
├── app/
│   ├── __init__.py
│   └── main.py
├── fastapi-s3.service
├── requirements.txt
└── screenshots/
    └── .gitkeep
```

Listo para que el estudiante:

1. Cree el venv local, instale dependencias y valide los endpoints en `http://127.0.0.1:8000/docs` (capturas 02, 05, 06, 07).
2. Tome las capturas del código en el editor (01, 04).
3. Cree los recursos AWS (bucket S3, rol IAM, instancia EC2, Security Group) y tome las capturas correspondientes (03, 08, 09).
4. Edite el placeholder en `fastapi-s3.service`, lo suba a la instancia y active el servicio (captura 10).
5. Acceda al Swagger público `http://<EC2-IP>:8000/docs` y tome las capturas finales (11, 12, 13).
6. Suba todo a un repositorio independiente de GitHub para el Punto 2.

---

## Turno 4

### Prompt del usuario

> Read the point 1 readme and use its style to indicate me how to deploy the services needed in the instances. Also note to the teacher that this service won't keep live since its EC and it consumes too much money and credits TwT

### Acciones del asistente

1. Releyó el `README.md` del Punto 1 (estilo: comandos explícitos por sub-ítem, bloques de "Alternativa CLI", flujo lineal).
2. Insertó una **caja destacada al inicio del README** ("Aviso al profesor — la instancia no se mantiene en línea") explicando que la EC2 se apaga después de tomar las evidencias porque mantener cómputo + IP pública en AWS consume créditos rápidamente. Las screenshots **08–13** son la evidencia, y el repo basta para reproducir el despliegue.
3. **Reescribió el sub-ítem `g`** en tres bloques al estilo Punto 1:
   - **g.1 — Prerrequisitos AWS** (bucket S3, política IAM con JSON mínimo, rol IAM, instancia EC2 + SG).
   - **g.2 — Subir el código a la instancia** (`scp` + alternativa `git clone`).
   - **g.3 — Setup dentro de la instancia** (`dnf install python3.11`, venv, `pip install`, smoke test con `uvicorn` antes de instalar el servicio).
4. **Expandió el sub-ítem `h`** con la secuencia explícita paso a paso:
   - `sed` para reemplazar el placeholder del bucket.
   - `cp` a `/etc/systemd/system/`.
   - `daemon-reload` → `enable --now` → `status` → `journalctl`.
   - Sección extra de "comandos útiles para depurar" incluyendo `systemctl stop` + `disable` (alineado con el aviso del inicio: apagar el servicio al terminar para no quemar créditos).
5. Registró este Turno 4 en `PROMPTS.md`.

### Respuesta del asistente

El README ahora cumple tres cosas adicionales:

- **Transparencia con el profesor** sobre por qué la URL puede no responder al momento de calificar (la evidencia visual queda en las capturas y el repositorio).
- **Guía de despliegue reproducible** al estilo Punto 1: comandos explícitos, copia-pegables, en orden, con anotaciones de qué hace cada uno.
- **Buenas prácticas operativas** documentadas (smoke test antes de systemd, comandos de depuración, apagado limpio del servicio al terminar).

No se generaron archivos nuevos; solo se editaron `README.md` y `PROMPTS.md`.

---

_Este archivo se actualiza en cada interacción posterior con un nuevo bloque `## Turno N`._
