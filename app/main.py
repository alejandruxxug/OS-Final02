"""FastAPI service to upload images to S3 (organized by user) and to retrieve
them via a presigned URL together with their S3 storage date.

Punto 2 - Final OS 2026-1 (Universidad EIA). Deployed on an EC2 instance and
exposed publicly on port 8000. AWS credentials come from the instance's IAM
role (no secrets in source).
"""

import os
from typing import Final

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse

S3_BUCKET: Final[str] = os.environ.get("S3_BUCKET", "")
AWS_REGION: Final[str] = os.environ.get("AWS_REGION", "us-east-1")

ALLOWED_EXTENSIONS: Final[set[str]] = {".png", ".jpg", ".jpeg"}
ALLOWED_CONTENT_TYPES: Final[set[str]] = {"image/png", "image/jpeg"}

PNG_MAGIC: Final[bytes] = b"\x89PNG\r\n\x1a\n"
JPEG_MAGIC: Final[bytes] = b"\xff\xd8\xff"

app = FastAPI(
    title="FastAPI S3 Image Service",
    description=(
        "Sube imágenes (PNG/JPG/JPEG) a S3 organizadas por usuario y "
        "recupera URLs prefirmadas con la fecha de almacenamiento."
    ),
    version="1.0.0",
)

s3 = boto3.client("s3", region_name=AWS_REGION)


def _ext_of(filename: str) -> str:
    return os.path.splitext(filename or "")[1].lower()


def _validate_magic_bytes(head: bytes, ext: str) -> bool:
    if ext == ".png":
        return head.startswith(PNG_MAGIC)
    if ext in {".jpg", ".jpeg"}:
        return head.startswith(JPEG_MAGIC)
    return False


@app.get("/", tags=["health"])
def healthcheck() -> dict[str, str]:
    return {"status": "ok", "service": "fastapi-s3"}


@app.post(
    "/upload",
    status_code=status.HTTP_201_CREATED,
    tags=["images"],
    summary="Sube una imagen PNG/JPG/JPEG a S3 bajo el prefijo del usuario.",
)
async def upload_image(
    username: str = Form(..., min_length=1, description="Nombre del usuario propietario."),
    file: UploadFile = File(..., description="Imagen PNG o JPG/JPEG."),
):
    if not S3_BUCKET:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="S3_BUCKET no configurado en el entorno del servidor.",
        )

    ext = _ext_of(file.filename)
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"Extensión '{ext or '(ninguna)'}' no permitida. "
                f"Formatos válidos: {sorted(ALLOWED_EXTENSIONS)}."
            ),
        )

    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"Content-Type '{file.content_type}' no permitido. "
                f"Esperado: {sorted(ALLOWED_CONTENT_TYPES)}."
            ),
        )

    head = await file.read(8)
    if not _validate_magic_bytes(head, ext):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "El contenido del archivo no corresponde a una imagen "
                f"{ext.lstrip('.').upper()} real (magic bytes inválidos)."
            ),
        )
    await file.seek(0)

    key = f"users/{username}/{file.filename}"
    try:
        s3.upload_fileobj(
            file.file,
            S3_BUCKET,
            key,
            ExtraArgs={"ContentType": file.content_type},
        )
    except ClientError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error subiendo a S3: {exc.response.get('Error', {}).get('Message', str(exc))}",
        ) from exc

    return {
        "username": username,
        "filename": file.filename,
        "bucket": S3_BUCKET,
        "s3_key": key,
        "content_type": file.content_type,
    }


@app.get(
    "/images/{username}/{image_name}",
    tags=["images"],
    summary="Devuelve una URL prefirmada y la fecha de almacenamiento de la imagen.",
)
def get_image(username: str, image_name: str):
    if not S3_BUCKET:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="S3_BUCKET no configurado en el entorno del servidor.",
        )

    key = f"users/{username}/{image_name}"

    try:
        head = s3.head_object(Bucket=S3_BUCKET, Key=key)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code")
        if code in {"404", "NoSuchKey", "NotFound"}:
            return JSONResponse(
                status_code=status.HTTP_404_NOT_FOUND,
                content={
                    "detail": (
                        f"No se encontró la imagen '{image_name}' para el usuario "
                        f"'{username}' en el bucket '{S3_BUCKET}'."
                    )
                },
            )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error consultando S3: {exc.response.get('Error', {}).get('Message', str(exc))}",
        ) from exc

    try:
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": S3_BUCKET, "Key": key},
            ExpiresIn=3600,
        )
    except ClientError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error generando presigned URL: {exc}",
        ) from exc

    return {
        "username": username,
        "image_name": image_name,
        "bucket": S3_BUCKET,
        "s3_key": key,
        "stored_at": head["LastModified"].isoformat(),
        "content_type": head.get("ContentType"),
        "size_bytes": head.get("ContentLength"),
        "url": url,
        "url_expires_in_seconds": 3600,
    }
