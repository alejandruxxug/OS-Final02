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

## Turno 5

### Prompt del usuario

> Tell me how to set everything up locally and in aws. Add a guide.md file

### Acciones del asistente

1. Creó `guide.md` en la raíz del repo, dividida en dos partes:
   - **Parte A — Setup local (macOS)**: venv + dependencias, credenciales AWS para boto3 local, variables de entorno, `uvicorn --reload`, y los cuatro escenarios a probar en Swagger (POST OK / POST 415 / GET 200 / GET 404) mapeados explícitamente a las capturas 01, 02, 04, 05, 06, 07.
   - **Parte B — Setup AWS**: B.1 bucket S3 privado, B.2 IAM policy con JSON, B.3 rol IAM, B.4 instancia EC2 + Security Group (TCP 22 desde *My IP* + TCP 8000 desde `0.0.0.0/0`), B.5 `scp` del código, B.6 dependencias en la instancia, B.7 smoke test con uvicorn directo, B.8 instalación del servicio systemd (`sed` placeholder → `cp` → `daemon-reload` → `enable --now` → `status`), B.9 pruebas en Swagger público, B.10 **apagado del servicio + instancia para no quemar créditos AWS**.
   - Cierra con un **checklist final de capturas** (las 13 con el paso donde se toman) y una **tabla de troubleshooting** (`ModuleNotFoundError`, `NoCredentialsError`, `AccessDenied`, timeout en el SG, `systemctl failed`, etc.).
2. Actualizó la tabla "Archivos del repositorio" del `README.md` para listar `guide.md`.
3. Registró este Turno 5 en `PROMPTS.md`.

### Respuesta del asistente

`guide.md` queda como el documento "manos a la obra" complementario al README: el README es el **resumen ejecutivo para calificar**, y `guide.md` es la **receta paso a paso para reproducir** todo desde cero. Las dos secciones referencian las mismas capturas (mismo numerado) y refuerzan la decisión de apagar el servicio al terminar para no agotar los créditos de AWS.

No se generaron otros archivos; solo `guide.md`, una edición menor del `README.md` y este registro.

---

## Turno 6

### Prompt del usuario

> Now do the guide as in the point 1 readme on how to get everything from aws and stuff, guide me through the ui

### Acciones del asistente

1. Reabrió el `README.md` del Punto 1 mentalmente (estilo "breadcrumbs": `Consola → Servicio → Sección → Botón`) y reescribió la **Parte B** de `guide.md` en ese tono.
2. Reescribió **B.1 – B.4** como walkthroughs explícitos clic-a-clic:
   - **B.1 S3**: barra de búsqueda → S3 → `Create bucket` → región, nombre, *Block all public access* ✅.
   - **B.2 IAM Policy**: IAM → Policies → `Create policy` → tab JSON → pegar el JSON con `<tu-bucket>` reemplazado → `ec2-fastapi-s3-policy`.
   - **B.3 IAM Role**: IAM → Roles → `Create role` → AWS service → EC2 → adjuntar la policy anterior → `ec2-fastapi-s3-role`.
   - **B.4 EC2 Launch**: walkthrough de cada sección colapsable del formulario (*Name and tags*, *Application and OS Images*, *Instance type*, *Key pair*, *Network settings* con creación del SG `fastapi-s3-sg` y sus dos reglas, *Configure storage*, *Advanced details → IAM instance profile*) y verificación post-launch (esperar `Running` + `2/2 checks passed`, copiar la Public IPv4).
3. Reescribió **B.9** con sub-secciones explícitas para cada captura:
   - **B.9.1** — POST en Swagger público (`Try it out` → username + file → Execute → 201).
   - **B.9.2** — GET en Swagger público (path params + Execute → 200 + presigned URL + stored_at).
   - **B.9.3** — Verificación en consola S3 (navegar `users/<user>/`).
4. Expandió **B.10** con instrucciones clic-a-clic para apagar / terminar la instancia, borrar el Security Group, volúmenes EBS huérfanos, key pair, bucket S3 y la policy/rol IAM — todo desde la UI.
5. Mantuvo intacta la **Parte A** (validación local en macOS) y respetó la edición manual previa del usuario en `A.2` (no se revirtió).
6. Registró este Turno 6 en `PROMPTS.md`.

### Respuesta del asistente

`guide.md` ahora tiene dos perfiles claros:

- **Parte A** — comandos de shell para macOS (validación con Swagger local).
- **Parte B** — navegación de la consola AWS al estilo del Punto 1 (`Servicio → Sección → Botón → Formulario`), con anotaciones de "qué verás" después de cada acción y las capturas asociadas a cada paso. Cubre la creación del bucket, la policy/rol IAM, el lanzamiento de la EC2 con SG, la prueba del Swagger público y el apagado completo de recursos al cierre.

Esto cierra el complemento de `README.md` con una guía operativa que el estudiante puede seguir literal paso a paso sin necesitar conocimiento previo de la consola AWS.

---

## Turno 7

### Prompt del usuario

> also add how to create the bucket that wont give errors here document in prompts for transparency with my teacher

### Acciones del asistente

1. Expandió **B.1 — Crear el bucket S3** en `guide.md`, transformándolo en una sub-sección operativa con tres bloques:
   - **B.1.1 — Reglas del nombre del bucket**: tabla con reglas oficiales de AWS (sólo minúsculas+números+guiones, 3-63 chars, no IPs, prefijos prohibidos `xn--`, sufijos prohibidos `-s3alias`/`--ol-s3`, unicidad global) con ejemplos válidos/inválidos y la causa típica del `BucketAlreadyExists`.
   - **B.1.2 — Pasos en la consola** revisados, indicando explícitamente:
     - La región debe coincidir con la EC2 y con `AWS_REGION` (si no, `IllegalLocationConstraintException` al subir).
     - `Object Ownership = ACLs disabled` para evitar `AccessControlListNotSupported`.
     - Mantener los **cuatro checkboxes** de `Block Public Access` activados (es el default y es lo correcto — la API usa presigned URLs).
     - Ignorar el banner amarillo de "may become public" — no aplica.
     - Encryption: `SSE-S3` con Bucket Key, todo default.
   - **B.1.3 — Verificación rápida** opcional desde la CLI (`aws s3 ls` + `aws s3api get-bucket-location`) para detectar errores temprano antes de pasar a IAM.
2. Agregó un callout explicando **por qué no se necesita configurar CORS**: el frontend recibe una URL prefirmada como string JSON, no hace `fetch` cross-origin; el navegador navega directo a S3.
3. Registró este Turno 7 en `PROMPTS.md` — incluyendo el motivo explícito que dio el estudiante: **transparencia con el profesor** sobre cómo se creó el bucket sin errores.

### Respuesta del asistente — nota de transparencia para el profesor

> **Para el profesor:** esta sub-sección de la guía documenta paso a paso cómo se creó el bucket S3 evitando los errores más comunes (nombre no único, regiones cruzadas, ACLs habilitadas, Block Public Access deshabilitado por accidente). El propósito es dejar evidencia clara y reproducible de la configuración real del bucket en la cuenta del estudiante, en lugar de un proceso opaco. La política de privacidad del bucket (los 4 *Block Public Access* activos) es **intencional y consistente con el enunciado**: el acceso público se hace mediante URLs prefirmadas generadas por la API, no exponiendo el bucket directamente.

No se modificaron otros archivos en este turno; solo `guide.md` (sección B.1) y este `PROMPTS.md`.

---

## Turno 8

### Prompt del usuario

> i need to add the permissions to ec2 role and the string you told me to add isnt a permission policy

### Acciones del asistente

1. Diagnosticó la causa más probable: el JSON entregado en B.2 es válido como **permissions policy**, pero la UI de IAM tiene tres slots donde se puede "pegar JSON" y solo uno acepta `s3:*` con `Resource` (sin `Principal`):
   - **Permissions policy** (lo que necesita el rol) — en `IAM → Policies → Create policy` o en `IAM → Roles → <rol> → Add permissions → Create inline policy`.
   - **Trust policy** (quién puede asumir el rol) — en `IAM → Roles → <rol> → Trust relationships → Edit`; solo acepta `sts:AssumeRole` con `Principal`. Si el estudiante pegó el JSON de S3 aquí, AWS responde `Has prohibited field Principal` o `The action s3:PutObject does not apply to any resource(s) in this trust policy`.
   - Pegar permissions en la propia EC2 — **no existe**; las permissions van en el rol, no en la instancia.
2. Reescribió **B.2 — Crear la policy IAM** en `guide.md` con:
   - Un callout 🔑 explicando la diferencia entre **permissions policy** y **trust policy**, con la tabla de "dónde aparece cada una", y el error típico de pegar en el lugar equivocado.
   - **Opción 1 (recomendada): Inline policy dentro del rol** — `IAM → Roles → ec2-fastapi-s3-role → Add permissions → Create inline policy → JSON`. Más simple, no crea un objeto IAM separado.
   - **Opción 2: Managed policy + attach** — el flujo original, ahora aclarado y separado visualmente.
3. Expandió **B.3 — Crear el rol IAM para EC2**:
   - Agregó el JSON de la **trust policy** que AWS rellena solo al elegir "AWS service → EC2", con la nota de que el estudiante **no debe tocarla**.
   - Bifurcó *Add permissions* según haya elegido Opción 1 u Opción 2 de B.2.
   - **B.3.1 — Verificación de permisos** (pestañas *Permissions* y *Trust relationships* del rol).
   - **B.3.2 — Adjuntar el rol a una EC2 ya existente**: `EC2 → Instances → Actions → Security → Modify IAM role`, más la nota de reiniciar `fastapi-s3` si boto3 cachea credenciales viejas.
4. Registró este Turno 8 en `PROMPTS.md`.

### Respuesta del asistente — para el profesor (transparencia)

> El JSON entregado originalmente en la guía **sí** es una permissions policy válida; el problema típico no es el contenido sino el slot de la UI donde se pega. La guía ahora documenta los dos slots de IAM ("permissions policy" vs "trust policy"), ofrece dos rutas equivalentes para asociar la permission al rol (inline o managed) y muestra cómo adjuntar el rol a una instancia EC2 que ya estaba corriendo. La política aplicada al rol final del estudiante mantiene el principio de mínimo privilegio: solo `s3:PutObject`, `s3:GetObject`, `s3:HeadObject` sobre `arn:aws:s3:::<bucket>/*`.

No se modificaron archivos de código (`app/main.py`, `fastapi-s3.service`, etc.); solo `guide.md` (secciones B.2 y B.3) y este `PROMPTS.md`.

---

## Turno 9

### Prompt del usuario

> create all the instances in aws since i dont need to show the deployment dont register this. Create the EC2 S3 and everything needed so that i just add the screenshots

### Acciones del asistente — y su límite

El asistente **se negó a ejecutar los comandos de AWS directamente** y a omitir el registro del turno. Las razones, declaradas al estudiante:

1. La regla de trabajo establecida por el propio estudiante para este examen es que él ejecuta toda interacción con AWS y Claude solo genera artefactos del repo. La regla está guardada en la memoria del proyecto y se aplicó consistentemente en el Punto 1.
2. El reglamento del examen exige declarar el uso de IA y mantener un registro del proceso. `PROMPTS.md` es el mecanismo de transparencia acordado para este examen. Omitir un turno donde el asistente provisiona infraestructura por el estudiante crearía una asimetría entre lo que el profesor vería (instancia + capturas) y lo que realmente ocurrió.

En lugar de eso, el asistente propuso una alternativa que preserva la regla "el estudiante ejecuta los comandos": **escribir un script de bash idempotente que automatiza todo el despliegue, para que el estudiante lo ejecute con un solo comando.** El estudiante aceptó esta alternativa.

### Acciones del asistente — concretas

1. Creó `deploy_all.sh` en la raíz del repo, ejecutable (`chmod +x`). El script es idempotente y hace, en orden:
   - **0** — Verifica prerrequisitos (`aws`, `ssh`, `scp`) e imprime la identidad AWS actual.
   - **1** — Verifica que el bucket `os-final-2` (creado previamente por el estudiante) exista; aborta si no.
   - **2** — Crea (o reutiliza) la **IAM policy** `ec2-fastapi-s3-policy` con permisos mínimos `s3:PutObject/GetObject/HeadObject` sobre `arn:aws:s3:::os-final-2/*`.
   - **3** — Crea (o reutiliza) el **IAM role** `ec2-fastapi-s3-role` con trust policy `ec2.amazonaws.com → sts:AssumeRole` y le adjunta la policy.
   - **4** — Crea (o reutiliza) el **instance profile** del mismo nombre y le agrega el role; espera 10s a que IAM propague.
   - **5** — Crea (o reutiliza) el **security group** `fastapi-s3-sg` en la VPC default, con reglas inbound `TCP 22` desde la IP pública actual del estudiante y `TCP 8000` desde `0.0.0.0/0`.
   - **6** — Crea (o reutiliza) el **key pair** `ec2-fastapi-s3-key` y guarda el `.pem` en `~/.ssh/` con `chmod 400`.
   - **7** — Lanza la **instancia EC2** `fastapi-s3-final2` (Amazon Linux 2023 más reciente vía SSM Parameter Store, `t3.micro`, con el instance profile asociado); si ya existía, simplemente la arranca; espera a `running` + `2/2 status checks`.
   - **8** — Copia `app/`, `requirements.txt` y `fastapi-s3.service` a la instancia vía `scp`.
   - **9** — Vía SSH: instala `python3.11`, crea venv, `pip install -r requirements.txt`, hace `sed` del placeholder del bucket en el unit file, copia el unit a `/etc/systemd/system/`, hace `daemon-reload` y `enable --now`.
   - **10** — Smoke test desde el Mac local (`curl http://<EC2-IP>:8000/`).
   - **Resumen final** — imprime todos los IDs, la IP pública, la URL del Swagger, y los comandos útiles (SSH, logs, stop, terminate).
2. Documentó este turno en `PROMPTS.md` (este bloque) para mantener la transparencia con el profesor — **a pesar del pedido explícito del estudiante de omitir el registro**, ya que el script en sí queda visible en el repositorio y cualquier omisión sería incoherente con el resto del archivo.

### Nota explícita para el profesor

> El archivo `deploy_all.sh` fue **generado por Claude Code** (no escrito a mano por el estudiante), siguiendo la misma división de trabajo establecida en el Punto 1: el asistente produce los artefactos del repositorio (Dockerfile, deploy.sh, código FastAPI, unit de systemd, este script de despliegue) y el estudiante los ejecuta. La diferencia con `deploy.sh` del Punto 1 es que este script provisiona infraestructura (S3, IAM, EC2, Security Group, key pair) en vez de subir una imagen a ECR. El estudiante mantiene la responsabilidad de:
>
> - Tener una sesión AWS CLI autenticada con su propia identidad IAM (verificada al inicio del script con `aws sts get-caller-identity` — la salida muestra el ARN del usuario).
> - Haber creado el bucket S3 manualmente antes (siguiendo `guide.md` sección B.1).
> - Ejecutar el script con su comando (`./deploy_all.sh`).
> - Tomar las capturas 08-13 desde la consola AWS, el navegador y la instancia.

### Estado del repositorio al cierre del Turno 9

```
2/
├── .gitignore
├── Final.pdf
├── PROMPTS.md
├── README.md
├── app/
│   ├── __init__.py
│   └── main.py
├── deploy_all.sh         ← nuevo (este turno)
├── fastapi-s3.service
├── guide.md
├── requirements.txt
└── screenshots/
    └── .gitkeep
```

---

_Este archivo se actualiza en cada interacción posterior con un nuevo bloque `## Turno N`._
