# Guía de despliegue — Punto 2 (FastAPI + S3 en EC2)

Guía paso a paso para reproducir el despliegue completo desde cero. Está dividida en dos partes: **Parte A — Local (macOS)** para el sub-ítem **f** del enunciado, y **Parte B — AWS** para los sub-ítems **g**, **h** e **i**.

> Todos los comandos se asumen ejecutados desde la raíz del repo (`Final/2/`) salvo que se indique lo contrario. Reemplaza `<tu-bucket>` y `<EC2-Public-IP>` con los valores reales.

---

## Parte A — Setup local (macOS) para validación con Swagger

Objetivo: levantar la API en `http://127.0.0.1:8000/docs` para probar ambos endpoints y tomar las **capturas 01, 02, 04, 05, 06 y 07**.

### A.1 — Python virtual environment

```bash
cd /Users/urrexx/Documents/Uni/3rdSemester/OS/Final/2
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### A.2 — Credenciales AWS para boto3 (local)

`boto3` necesita credenciales para hablar con S3 desde tu Macaws sts get-caller-identity  # verifica que el perfil funcione. Usa las que ya tengas configuradas en `~/.aws/credentials` (perfil `default`) o exporta variables:

```bash
# Opción 1: perfil ya configurado en ~/.aws/credentials
aws sts get-caller-identity  # verifica que el perfil funcione

# Opción 2: exportar temporalmente
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...   # si usas credenciales de AWS Academy
```

Las credenciales locales solo se usan para la validación del sub-ítem **f**. En EC2 (Parte B) la app NO necesita keys porque lee del rol IAM de la instancia.

### A.3 — Variables de entorno de la app

```bash
export S3_BUCKET=<tu-bucket>
export AWS_REGION=us-east-1
```

> El bucket ya debe existir en `us-east-1` antes de arrancar la app (ver paso **B.1**). Si aún no lo creas, puedes hacerlo primero y volver acá.

### A.4 — Arrancar uvicorn en modo desarrollo

```bash
uvicorn app.main:app --reload
```

Salida esperada:

```
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Application startup complete.
```

### A.5 — Probar en Swagger

Abre `http://127.0.0.1:8000/docs` en el navegador y prueba estos cuatro escenarios (cada uno es una captura):

1. **POST /upload con imagen PNG/JPG válida** → 201 con JSON de respuesta → **captura 07**.
2. **POST /upload con un `.txt` o cualquier extensión no permitida** → 415 → **captura 02**.
3. **GET /images/{username}/{image_name}** con la imagen recién subida → 200 con `url` prefirmada y `stored_at` → **captura 05**.
4. **GET /images/{username}/{image_name}** con un nombre inexistente → 404 con mensaje claro → **captura 06**.

Para las capturas **01** y **04**: abre `app/main.py` en tu editor y muestra respectivamente el bloque del `POST /upload` y el del `GET /images/...`.

Cuando termines, `Ctrl+C` apaga uvicorn.

---

## Parte B — Setup en AWS (paso a paso por la consola)

Objetivo: dejar la API corriendo como servicio systemd en una instancia EC2 pública, con un bucket S3 privado detrás. Tomar las **capturas 03, 08, 09, 10, 11, 12, 13**.

> 🧭 Antes de empezar: inicia sesión en la consola AWS, **selecciona la región `US East (N. Virginia) us-east-1`** en la esquina superior derecha y confirma con `aws sts get-caller-identity` que estás en la cuenta correcta. Todos los recursos que crees deben quedar en la misma región.

---

### B.1 — Crear el bucket S3 (sin que dé errores)

**Ruta:** consola → barra de búsqueda → escribir **`S3`** → entrar al servicio **S3**.

#### B.1.1 — Reglas del nombre del bucket (la causa #1 de errores)

Los nombres de buckets son **globales para todo AWS** (no por cuenta, no por región). AWS rechaza la creación si el nombre incumple alguna regla:

| Regla | Ejemplo válido | Ejemplo inválido |
|---|---|---|
| Solo minúsculas, números y guiones (`-`) | `alejandro-os-final2-2026` | `Alejandro_OS_Final2` ❌ (mayúsculas + `_`) |
| Entre 3 y 63 caracteres | `os-final2-aug` | `os` ❌ (muy corto) |
| Debe empezar y terminar con letra o número | `final2-bucket` | `-final2-` ❌ |
| No puede parecer una IP | `bucket-1-2-3` | `192.168.1.1` ❌ |
| No puede empezar con `xn--` ni terminar con `-s3alias` / `--ol-s3` | — | `xn--mibucket` ❌ |
| Tiene que ser **único en todo AWS** | — | `test`, `images`, `data` ❌ (ya tomados) |

**Consejo práctico:** prefija con algo personal para garantizar unicidad. Ejemplo: `<tu-nombre>-os-final2-<año>` → `alejandro-os-final2-2026`.

Si al darle **`Create bucket`** AWS responde:
```
BucketAlreadyExists: The requested bucket name is not available.
```
no es un bug — el nombre ya lo tiene otra cuenta. Cambia el nombre y reintenta.

#### B.1.2 — Pasos en la consola

1. Botón naranja **`Create bucket`** (esquina superior derecha).
2. **General configuration**:
   - **AWS Region**: `US East (N. Virginia) us-east-1`. **Importante:** debe ser la misma región donde lanzarás la EC2 (paso B.4) y la misma de tu `AWS_REGION=us-east-1`. Si las regiones no coinciden, `boto3` falla con `IllegalLocationConstraintException` al subir objetos.
   - **Bucket name**: tu nombre único siguiendo las reglas de B.1.1.
   - **Copy settings from existing bucket**: déjalo vacío.
3. **Object Ownership**: `ACLs disabled (recommended)`. **No activar ACLs** — la app no las usa y activarlas obliga a configurar permisos extra que generan errores `AccessControlListNotSupported`.
4. **Block Public Access settings for this bucket**:
   - **Deja los CUATRO checkboxes activados** ✅✅✅✅ (es el default). Esto es lo correcto: el bucket queda privado y la API entrega presigned URLs.
   - Si AWS muestra el banner amarillo *"Turning off block all public access might result in this bucket and the objects within becoming public"*, **ignóralo** — no estás apagando nada.
5. **Bucket Versioning**: `Disable` (default). No lo necesitamos.
6. **Tags**: opcional, déjalo vacío.
7. **Default encryption**:
   - **Encryption type**: `Server-side encryption with Amazon S3 managed keys (SSE-S3)` (default).
   - **Bucket Key**: `Enable` (default). No tocar.
8. **Advanced settings → Object Lock**: `Disable` (default).
9. Click **`Create bucket`** al final.

Verás un banner verde: `Successfully created bucket "<tu-bucket>"` y el bucket aparece en el listado **Buckets**.

#### B.1.3 — Verificación rápida (opcional, desde tu Mac)

Antes de seguir con la policy IAM, valida que tu CLI puede ver el bucket:

```bash
aws s3 ls s3://<tu-bucket>/  # debe responder vacío, sin error
aws s3api get-bucket-location --bucket <tu-bucket>
# → {"LocationConstraint": null}  (null = us-east-1, es lo esperado)
```

Si la respuesta es `AccessDenied`, tu usuario IAM personal no tiene permisos sobre buckets propios — revisa que estés autenticado con la cuenta correcta (`aws sts get-caller-identity`). Si es `NoSuchBucket`, verifica que escribiste bien el nombre.

> **¿Por qué no necesitas configurar CORS?** El flujo de esta API es: el frontend (Swagger) recibe una **URL prefirmada** como string JSON, y el usuario hace click en ese link — el navegador navega directo a S3, no hace `fetch` cross-origin desde JavaScript. Por eso este bucket funciona sin reglas de CORS.

---

### B.2 — Crear la policy IAM

> 🔑 **Importante: dos tipos de "policy" que IAM no diferencia bien en la UI**
>
> | Tipo | Para qué sirve | Dónde aparece |
> |---|---|---|
> | **Permissions policy** | Decir *qué puede hacer* el rol/usuario (ej. `s3:PutObject`). | `IAM → Policies` (managed) **o** `IAM → Roles → <rol> → Add permissions → Create inline policy`. |
> | **Trust policy** | Decir *quién puede asumir* el rol (ej. el servicio EC2). | Solo dentro del rol: `IAM → Roles → <rol> → Trust relationships → Edit`. Aquí va `sts:AssumeRole`, **no** `s3:*`. |
>
> El JSON que aparece más abajo es **una permissions policy**. Si te aparece un error tipo `Has prohibited field Principal` o `The action s3:PutObject does not apply to any resource(s) in this trust policy`, lo pegaste en el campo equivocado (la *trust policy*). La *trust policy* del rol se configura sola cuando eliges "AWS service → EC2" en B.3, no la editas manualmente.

Hay **dos formas** equivalentes de crear esta policy. Elige una.

#### Opción 1 (recomendada) — Inline policy dentro del rol

Es más simple porque no crea un objeto IAM separado. Si aún no creaste el rol, hazlo primero en B.3 y luego vuelve aquí.

**Ruta:** `IAM → Roles → ec2-fastapi-s3-role → pestaña "Permissions" → botón "Add permissions" → "Create inline policy"`.

1. Tab **`JSON`** (no `Visual`).
2. Borra el contenido por defecto y pega:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:PutObject",
           "s3:GetObject",
           "s3:HeadObject"
         ],
         "Resource": "arn:aws:s3:::<tu-bucket>/*"
       }
     ]
   }
   ```

   Reemplaza `<tu-bucket>` por el nombre real del paso B.1. **No agregues `Principal`** — las inline policies no lo llevan.

3. **`Next`**.
4. **Policy name**: `ec2-fastapi-s3-policy` → **`Create policy`**.

Verás la policy listada bajo "Permissions policies" del rol.

#### Opción 2 — Managed policy separada + attach

Si prefieres tener la policy como objeto reutilizable:

**Ruta:** `IAM → Policies → Create policy`.

1. Tab **`JSON`** → pegar el mismo JSON de arriba.
2. **`Next`** → **Name**: `ec2-fastapi-s3-policy` → **`Create policy`**.
3. Ahora ve al rol: `IAM → Roles → ec2-fastapi-s3-role → Add permissions → Attach policies` → busca `ec2-fastapi-s3-policy` → ✅ → **`Add permissions`**.

---

### B.3 — Crear el rol IAM para EC2

**Ruta:** `IAM` → panel izquierdo, **Roles** → botón **`Create role`**.

1. *Select trusted entity*:
   - **Trusted entity type**: `AWS service`.
   - **Service or use case**: `EC2`.
   - **Use case**: `EC2` (la opción simple, no `EC2 Role for AWS Systems Manager`).
   - **`Next`**.

   👉 Al elegir "EC2", AWS **rellena automáticamente la trust policy** con el statement correcto:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Service": "ec2.amazonaws.com" },
       "Action": "sts:AssumeRole"
     }]
   }
   ```
   No tienes que tocarla. Esto es lo que permite que la instancia EC2 "se haga pasar" por el rol y obtenga credenciales temporales.

2. *Add permissions*:
   - Si seguiste **Opción 2** de B.2: busca `ec2-fastapi-s3-policy` → ✅ → **`Next`**.
   - Si seguiste **Opción 1** (inline policy): déjala vacía aquí → **`Next`**. La permissions policy la agregarás justo después de crear el rol.

3. *Name, review, and create*:
   - **Role name**: `ec2-fastapi-s3-role`.
   - **Description** (opcional): `Rol que asume la instancia EC2 del Punto 2 para acceder a S3.`
4. **`Create role`**.

Verás `Role ec2-fastapi-s3-role created`. Si elegiste Opción 1 → ahora vuelve a B.2 Opción 1 y crea la inline policy.

#### B.3.1 — Verificación de permisos en el rol

Antes de pasar a la EC2, confirma:

**Ruta:** `IAM → Roles → ec2-fastapi-s3-role`.

- Pestaña **Permissions**: debe listar `ec2-fastapi-s3-policy` (managed o inline). Click para expandir → debe mostrar `s3:PutObject, s3:GetObject, s3:HeadObject` sobre `arn:aws:s3:::<tu-bucket>/*`.
- Pestaña **Trust relationships**: debe mostrar `Principal: ec2.amazonaws.com` y `Action: sts:AssumeRole`. No la modifiques.

#### B.3.2 — Adjuntar el rol a una EC2 *ya existente* (si ya la creaste sin el rol)

Si lanzaste la instancia antes de tener el rol listo, no tienes que recrearla. Se le puede adjuntar el instance profile en caliente:

**Ruta:** `EC2 → Instances` → marca la instancia → **`Actions → Security → Modify IAM role`**.

1. Dropdown **IAM role**: selecciona `ec2-fastapi-s3-role`.
2. **`Update IAM role`**.

Verás `IAM role successfully attached`. No requiere reiniciar la instancia — boto3 obtendrá credenciales del IMDS automáticamente en la próxima invocación.

> Si después de adjuntar el rol la app sigue dando `NoCredentialsError` o `AccessDenied`, **reinicia el servicio** dentro de la instancia: `sudo systemctl restart fastapi-s3`. boto3 cachea las credenciales y conviene forzar la recarga.

---

### B.4 — Lanzar la instancia EC2

**Ruta:** barra de búsqueda → **`EC2`** → panel izquierdo, **Instances** → botón naranja **`Launch instances`**.

Llena el formulario en este orden (cada bloque corresponde a una sección colapsable del formulario):

1. **Name and tags**
   - **Name**: `fastapi-s3-final2`.

2. **Application and OS Images (Amazon Machine Image)**
   - Selecciona **`Amazon Linux`** → en el dropdown debajo, deja la opción por defecto **`Amazon Linux 2023 AMI`** (`64-bit (x86)` ✅).

3. **Instance type**
   - Dropdown → **`t3.micro`** (o `t2.micro` si tu cuenta lo restringe).

4. **Key pair (login)**
   - **Key pair name**: selecciona tu `.pem` existente.
   - Si no tienes, **`Create new key pair`** → tipo `RSA`, formato `.pem` → **Create** (se descarga; luego `chmod 400 ~/.ssh/<archivo>.pem`).

5. **Network settings** → botón **`Edit`** (a la derecha del título).
   - **VPC**: default.
   - **Subnet**: cualquier `us-east-1a` / `us-east-1b` / ... default.
   - **Auto-assign public IP**: `Enable`.
   - **Firewall (security groups)**: selecciona **`Create security group`**.
     - **Security group name**: `fastapi-s3-sg`.
     - **Description**: `SSH + FastAPI :8000 para Punto 2`.
     - Verás una regla por defecto **SSH TCP 22**: cambia **Source type** a `My IP` (botón inferior **`Add security group rule`** si necesitas agregar otra).
     - Click **`Add security group rule`**:
       - **Type**: `Custom TCP`.
       - **Port range**: `8000`.
       - **Source type**: `Anywhere`.
       - **Source**: `0.0.0.0/0`.
       - (Description: `Swagger público FastAPI`).

6. **Configure storage**
   - Deja `1x 8 GiB gp3` (default).

7. **Advanced details** (sección colapsada al fondo — desplegar).
   - **IAM instance profile**: dropdown → **`ec2-fastapi-s3-role`** (el del paso B.3).
   - El resto, default.

8. Resumen *Summary* a la derecha → **`Launch instance`**.

Verás `Successfully initiated launch of instance (i-xxxxxxxxx)` → click en `View all instances`.

Espera ~30 segundos hasta que la columna **Instance state** diga `Running` y **Status check** diga `2/2 checks passed`. Selecciona la instancia y en la pestaña **Details** copia la **Public IPv4 address** — la llamaremos `<EC2-Public-IP>`.

📸 **Capturas a tomar aquí**:

- **08** — vista de **Instances** con tu instancia *Running* y la columna IPv4 visible (asegúrate que el nombre del usuario IAM esté visible en la barra superior).
- **09** — selecciona la instancia → pestaña **Security** → click en el link del *Security group* (`fastapi-s3-sg`) → pestaña **Inbound rules** → captura mostrando las dos reglas (TCP 22 y TCP 8000).

### B.5 — Subir el código a la instancia

Desde tu Mac (con la raíz del repo como working directory):

```bash
scp -i ~/.ssh/<tu-key>.pem -r \
    app fastapi-s3.service requirements.txt \
    ec2-user@<EC2-Public-IP>:/home/ec2-user/app-src/
```

> Si la conexión es rechazada: revisa el Security Group (puerto 22 abierto a tu IP) y que el archivo `.pem` tenga permisos `chmod 400 ~/.ssh/<tu-key>.pem`.

### B.6 — Setup de Python + dependencias en la instancia

Conéctate por SSH:

```bash
ssh -i ~/.ssh/<tu-key>.pem ec2-user@<EC2-Public-IP>
```

Dentro de la instancia:

```bash
# 1. Python 3.11 + git
sudo dnf install -y python3.11 python3.11-pip git

# 2. Layout que espera el unit file de systemd
mkdir -p /home/ec2-user/app
cp -r /home/ec2-user/app-src/app /home/ec2-user/app/
cp /home/ec2-user/app-src/requirements.txt /home/ec2-user/app/
cp /home/ec2-user/app-src/fastapi-s3.service /home/ec2-user/app/

cd /home/ec2-user/app

# 3. venv + dependencias
python3.11 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### B.7 — Smoke test (verificar antes de meter systemd)

```bash
# todavía dentro de /home/ec2-user/app, con .venv activo
export S3_BUCKET=<tu-bucket> AWS_REGION=us-east-1
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Si arranca con:

```
INFO:     Uvicorn running on http://0.0.0.0:8000
```

abre desde tu Mac:

```
http://<EC2-Public-IP>:8000/docs
```

y debe cargar el Swagger. Sube una imagen de prueba (debería responder `201`). Si todo OK, `Ctrl+C` para detener uvicorn y pasar a systemd.

### B.8 — Instalar el servicio systemd

```bash
# 1. Reemplazar el placeholder del bucket en el unit file
sed -i 's|<REEMPLAZAR-CON-NOMBRE-DEL-BUCKET>|<tu-bucket>|' \
    /home/ec2-user/app/fastapi-s3.service

# 2. Copiar al directorio de systemd
sudo cp /home/ec2-user/app/fastapi-s3.service /etc/systemd/system/

# 3. Recargar systemd para que detecte el nuevo unit
sudo systemctl daemon-reload

# 4. Habilitar y arrancar
sudo systemctl enable --now fastapi-s3

# 5. Verificar
sudo systemctl status fastapi-s3
```

Salida esperada (extracto):

```
● fastapi-s3.service - FastAPI S3 image service (Punto 2 OS Final 2026-1)
     Loaded: loaded (/etc/systemd/system/fastapi-s3.service; enabled; ...)
     Active: active (running) since ...
   Main PID: ... (uvicorn)
```

📸 **Captura 10** — la salida de `systemctl status fastapi-s3` con "active (running)" visible y reloj del sistema visible.

Logs en vivo (opcional, útil si algo falla):

```bash
sudo journalctl -u fastapi-s3 -f
```

### B.9 — Probar el Swagger público (mitad navegador + mitad consola AWS)

Desde tu Mac, abre en una pestaña del navegador:

```
http://<EC2-Public-IP>:8000/docs
```

#### B.9.1 — POST desde el Swagger público

1. Click en la fila **`POST /upload`** → botón **`Try it out`** (esquina derecha).
2. **username**: `alejandro` (o el usuario que quieras).
3. **file**: **`Choose File`** → selecciona una imagen `.png` o `.jpg`.
4. **`Execute`**.
5. En la sección **Server response** verás:
   - **Code**: `201`.
   - **Response body**: JSON con `bucket`, `s3_key=users/alejandro/<archivo>`, etc.

📸 **Captura 11** — todo el bloque del Swagger público mostrando el POST con respuesta 201 (URL de la barra del navegador debe mostrar `<EC2-Public-IP>:8000/docs`, reloj visible).

#### B.9.2 — GET desde el Swagger público

1. Click en la fila **`GET /images/{username}/{image_name}`** → **`Try it out`**.
2. **username**: el mismo del paso anterior.
3. **image_name**: el nombre exacto del archivo que subiste (ej. `perfil.png`).
4. **`Execute`**.
5. **Code** `200` con `url` prefirmada (link `https://...amazonaws.com/...?X-Amz-...`) y `stored_at` con fecha ISO.

📸 **Captura 12** — bloque del Swagger público con el GET y la respuesta JSON expandida (URL y `stored_at` legibles, reloj visible).

#### B.9.3 — Confirmar el objeto en la consola S3

**Ruta en la consola AWS:**

1. Barra de búsqueda → **`S3`** → click en el nombre del bucket `<tu-bucket>`.
2. En la lista de objetos del bucket verás la carpeta **`users/`** → click.
3. Dentro verás **`alejandro/`** (o el usuario que usaste) → click.
4. Verás el archivo recién subido con su tamaño y *Last modified* coincidiendo con el momento del POST.

📸 **Captura 13** — vista del objeto dentro de `users/<usuario>/` con el nombre IAM visible en la barra superior y el reloj visible.

> La **captura 03** se puede tomar acá mismo (es la misma vista de S3 con el prefijo de usuario) si todavía no la tomaste durante la validación local.

### B.10 — Apagar el servicio al terminar (proteger créditos AWS)

> ⚠️ Importante: una instancia EC2 *running* sigue facturando aunque no tengas tráfico. Apenas tomes todas las capturas, apaga el entorno.

#### B.10.1 — Detener el servicio dentro de la instancia (opcional)

```bash
sudo systemctl stop fastapi-s3
sudo systemctl disable fastapi-s3
```

#### B.10.2 — Apagar / terminar la instancia desde la consola AWS

**Ruta:** consola → **EC2 → Instances** → marca el ✅ de `fastapi-s3-final2`.

- Botón **`Instance state`** (arriba de la tabla):
  - **`Stop instance`** → la apaga pero la conserva. Deja de cobrar cómputo, sigue cobrando el volumen EBS (~$0.08/mes los 8 GiB — negligible).
  - **`Terminate instance`** → la destruye y libera EBS. Recomendado al cerrar definitivamente el ejercicio.
- Confirmar en el diálogo emergente.

#### B.10.3 — Limpieza opcional adicional desde la consola

- **Security Group** — EC2 → panel izquierdo, **Security Groups** → marca `fastapi-s3-sg` → **Actions → Delete security groups**. (Solo se puede borrar si ya no hay instancias usándolo; si terminaste la instancia, espera ~5 min a que el ENI se libere.)
- **Volumen EBS huérfano** — EC2 → panel izquierdo, **Volumes** → si quedó algún volumen `Available` (desasociado), marca → **Actions → Delete volume**. (Al `Terminate` la instancia, su volumen raíz se borra automáticamente si tiene *Delete on termination* en `true`, que es el default.)
- **Key pair** — EC2 → panel izquierdo, **Key Pairs** → solo bórralo si no piensas reutilizarlo en otro ejercicio.
- **Bucket S3** — S3 → click en `<tu-bucket>` → **Empty** (escribe `permanently delete` para confirmar) → de vuelta a la lista de buckets → marca el bucket → **Delete** → escribe el nombre exacto del bucket para confirmar.
- **Rol y policy IAM** — IAM → **Roles** → `ec2-fastapi-s3-role` → **Delete**. Luego IAM → **Policies** → busca `ec2-fastapi-s3-policy` → **Actions → Delete**. (IAM no cobra, pero ayuda a mantener la cuenta limpia.)

---

## Checklist final de capturas


| #   | Cuándo se toma                                                  |
| --- | --------------------------------------------------------------- |
| 01  | Parte A — editor con `app/main.py` mostrando `POST /upload`.    |
| 02  | Parte A.5 — Swagger local, POST con `.txt` devolviendo 415.     |
| 03  | Parte A.5 o B.9 — consola S3, objeto bajo `users/<usuario>/`.   |
| 04  | Parte A — editor con `app/main.py` mostrando `GET /images/...`. |
| 05  | Parte A.5 — Swagger local, GET con presigned URL.               |
| 06  | Parte A.5 — Swagger local, GET 404 con mensaje claro.           |
| 07  | Parte A.5 — Swagger local, POST exitoso 201.                    |
| 08  | Parte B.4 — consola EC2, instancia *running* con IP pública.    |
| 09  | Parte B.4 — Security Group con regla inbound 8000.              |
| 10  | Parte B.8 — `systemctl status fastapi-s3` activo.               |
| 11  | Parte B.9 — Swagger público, POST exitoso.                      |
| 12  | Parte B.9 — Swagger público, GET con presigned URL.             |
| 13  | Parte B.9 — consola S3, objeto subido desde el Swagger público. |


---

## Troubleshooting rápido


| Síntoma                                                                  | Causa probable                                                   | Fix                                                                                                            |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `ModuleNotFoundError: No module named 'multipart'`                       | Falta `python-multipart`                                         | `pip install -r requirements.txt` (ya está fijado).                                                            |
| Swagger local 500 al subir imagen                                        | `S3_BUCKET` no exportado o credenciales locales sin acceso       | `echo $S3_BUCKET`, `aws sts get-caller-identity`.                                                              |
| `NoCredentialsError` en EC2                                              | El rol IAM no se asoció a la instancia                           | EC2 → Actions → Security → Modify IAM role → `ec2-fastapi-s3-role`.                                            |
| `AccessDenied` en `PutObject`                                            | La policy no permite `PutObject` sobre `<tu-bucket>/`*           | Edita `ec2-fastapi-s3-policy` y revisa el ARN del recurso.                                                     |
| Connection timeout a `<EC2-IP>:8000`                                     | Security Group no abre 8000                                      | Agrega regla inbound TCP 8000 desde `0.0.0.0/0`.                                                               |
| `systemctl status` muestra `failed`                                      | `ExecStart` apunta a un binario inexistente                      | Verifica `/home/ec2-user/app/.venv/bin/uvicorn` con `ls -la`; reinstala el venv si falta.                      |
| El servicio arranca pero `journalctl` muestra `S3_BUCKET no configurado` | El `sed` del paso B.8 no se ejecutó                              | Edita `/etc/systemd/system/fastapi-s3.service` a mano y reemplaza el placeholder; `daemon-reload` + `restart`. |
| Imagen sube pero el Swagger devuelve 400 "magic bytes inválidos"         | El archivo está corrupto o no es realmente del formato declarado | Prueba con otra imagen PNG/JPG legítima.                                                                       |


