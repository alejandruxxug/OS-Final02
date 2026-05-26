#!/usr/bin/env bash
# =============================================================================
# deploy_all.sh — Provisión de toda la infraestructura AWS del Punto 2 en
# un solo comando. Idempotente: se puede re-ejecutar sin romper recursos
# existentes. Lee credenciales de tu perfil por defecto del AWS CLI.
#
# Recursos que crea/asegura:
#   - Verifica el bucket S3 (debe existir previamente — ver $BUCKET abajo).
#   - IAM policy:           ec2-fastapi-s3-policy
#   - IAM role:             ec2-fastapi-s3-role  (trust = ec2.amazonaws.com)
#   - Instance profile:     ec2-fastapi-s3-role
#   - Security group:       fastapi-s3-sg       (22 desde mi IP + 8000 público)
#   - Key pair:             ec2-fastapi-s3-key  (.pem en ~/.ssh/)
#   - EC2 instance:         fastapi-s3-final2   (Amazon Linux 2023, t3.micro)
#   - Sube código + instala dependencias + activa systemd fastapi-s3
#
# Uso:
#   chmod +x deploy_all.sh
#   ./deploy_all.sh
# =============================================================================

set -euo pipefail

# ---- Config -----------------------------------------------------------------
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
BUCKET="os-final-02"
POLICY_NAME="ec2-fastapi-s3-policy"
ROLE_NAME="ec2-fastapi-s3-role"
INSTANCE_PROFILE_NAME="$ROLE_NAME"
SG_NAME="fastapi-s3-sg"
KEY_NAME="ec2-fastapi-s3-key"
KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"
INSTANCE_NAME="fastapi-s3-final02"
INSTANCE_TYPE="t3.micro"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

bold() { printf "\n\033[1m▶ %s\033[0m\n" "$*"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$*"; }

# ---- 0. Prerequisites -------------------------------------------------------
bold "0. Verificando prerrequisitos"
command -v aws >/dev/null || { echo "aws CLI requerido"; exit 1; }
command -v ssh >/dev/null || { echo "ssh requerido"; exit 1; }
command -v scp >/dev/null || { echo "scp requerido"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
ok "AWS account: $ACCOUNT_ID"
ok "Identidad:   $USER_ARN"
ok "Región:      $AWS_REGION"

# ---- 1. Bucket exists -------------------------------------------------------
bold "1. Verificando bucket s3://$BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  ok "Bucket existe"
else
  echo "  ❌ Bucket s3://$BUCKET no existe o no tienes acceso."
  echo "     Créalo en la consola siguiendo guide.md sección B.1 y vuelve a correr."
  exit 1
fi

# ---- 2. IAM policy ----------------------------------------------------------
bold "2. IAM policy: $POLICY_NAME"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  ok "Policy ya existe: $POLICY_ARN"
else
  POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:HeadObject"],
    "Resource": "arn:aws:s3:::${BUCKET}/*"
  }]
}
EOF
)
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC" \
    --description "Punto 2 OS Final 2026-1 - acceso S3 desde EC2." >/dev/null
  ok "Policy creada"
fi

# ---- 3. IAM role with EC2 trust --------------------------------------------
bold "3. IAM role: $ROLE_NAME"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  ok "Role ya existe"
else
  TRUST=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST" \
    --description "Punto 2 OS Final 2026-1 - rol EC2 a S3." >/dev/null
  ok "Role creado con trust ec2.amazonaws.com"
fi

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" >/dev/null 2>&1 || true
ok "Policy adjuntada al role"

# ---- 4. Instance profile ----------------------------------------------------
bold "4. Instance profile: $INSTANCE_PROFILE_NAME"
if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  ok "Instance profile ya existe"
else
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null
  ok "Instance profile creado"
fi

if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME'] | length(@)" \
    --output text | grep -q "^0$"; then
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --role-name "$ROLE_NAME"
  ok "Role agregado al instance profile"
  warn "Esperando 10s a que IAM propague…"
  sleep 10
else
  ok "Role ya está en el instance profile"
fi

# ---- 5. Security group ------------------------------------------------------
bold "5. Security group: $SG_NAME"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query "Vpcs[0].VpcId" --output text)
ok "VPC default: $VPC_ID"

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "SSH + FastAPI :8000 (Punto 2)" \
    --vpc-id "$VPC_ID" \
    --query GroupId --output text)
  ok "SG creado: $SG_ID"
else
  ok "SG ya existe: $SG_ID"
fi

MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "${MY_IP}/32" >/dev/null 2>&1 \
  && ok "Ingress SSH 22 desde ${MY_IP}/32 agregado" \
  || ok "Ingress SSH 22 ya existe"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port 8000 --cidr 0.0.0.0/0 >/dev/null 2>&1 \
  && ok "Ingress TCP 8000 desde 0.0.0.0/0 agregado" \
  || ok "Ingress TCP 8000 ya existe"

# ---- 6. Key pair ------------------------------------------------------------
bold "6. Key pair: $KEY_NAME"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  if [ -f "$KEY_PATH" ]; then
    ok "Key pair y .pem local presentes ($KEY_PATH)"
  else
    echo "  ❌ El key pair $KEY_NAME existe en AWS pero no encuentro $KEY_PATH."
    echo "     Elimina el key pair en la consola y vuelve a correr, o restaura tu .pem."
    exit 1
  fi
else
  mkdir -p "$(dirname "$KEY_PATH")"
  aws ec2 create-key-pair --key-name "$KEY_NAME" \
    --query "KeyMaterial" --output text > "$KEY_PATH"
  chmod 400 "$KEY_PATH"
  ok "Key pair creado y guardado en $KEY_PATH"
fi

# ---- 7. EC2 instance --------------------------------------------------------
bold "7. EC2 instance: $INSTANCE_NAME"
EXISTING_INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
            "Name=instance-state-name,Values=running,pending,stopped,stopping" \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || echo "None")

if [ "$EXISTING_INSTANCE" != "None" ] && [ -n "$EXISTING_INSTANCE" ]; then
  INSTANCE_ID="$EXISTING_INSTANCE"
  ok "Instancia ya existe: $INSTANCE_ID"
  STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].State.Name" --output text)
  if [ "$STATE" = "stopped" ]; then
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
    ok "Instancia detenida → arrancada"
  fi
else
  AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query "Parameter.Value" --output text)
  ok "AMI:         $AMI_ID (latest Amazon Linux 2023)"
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" --output text)
  ok "Instancia lanzada: $INSTANCE_ID"
fi

bold "Esperando running + 2/2 status checks (~60-90s)…"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
ok "Instancia OK en $PUBLIC_IP"

# ---- 8. SCP code ------------------------------------------------------------
bold "8. Subiendo código"
SSH_OPTS="-i $KEY_PATH -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
for i in $(seq 1 30); do
  if ssh $SSH_OPTS ec2-user@"$PUBLIC_IP" "echo ready" >/dev/null 2>&1; then
    ok "SSH listo"
    break
  fi
  [ "$i" = "30" ] && { echo "  ❌ SSH no respondió tras 90s"; exit 1; }
  sleep 3
done

ssh $SSH_OPTS ec2-user@"$PUBLIC_IP" "mkdir -p /home/ec2-user/app-src"
scp $SSH_OPTS -r \
  "$REPO_DIR/app" \
  "$REPO_DIR/requirements.txt" \
  "$REPO_DIR/fastapi-s3.service" \
  ec2-user@"$PUBLIC_IP":/home/ec2-user/app-src/
ok "Código subido a /home/ec2-user/app-src/"

# ---- 9. Setup + systemd en la instancia -------------------------------------
bold "9. Instalando dependencias + systemd en la instancia"
ssh $SSH_OPTS ec2-user@"$PUBLIC_IP" "BUCKET='$BUCKET' bash -s" <<'REMOTE'
set -euo pipefail
sudo dnf install -y python3.11 python3.11-pip >/dev/null
mkdir -p /home/ec2-user/app
cp -r /home/ec2-user/app-src/app /home/ec2-user/app/
cp /home/ec2-user/app-src/requirements.txt /home/ec2-user/app/
cp /home/ec2-user/app-src/fastapi-s3.service /home/ec2-user/app/
cd /home/ec2-user/app
[ -d .venv ] || python3.11 -m venv .venv
.venv/bin/pip install --upgrade pip --quiet
.venv/bin/pip install -r requirements.txt --quiet
sed -i "s|<REEMPLAZAR-CON-NOMBRE-DEL-BUCKET>|${BUCKET}|" /home/ec2-user/app/fastapi-s3.service
sudo cp /home/ec2-user/app/fastapi-s3.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fastapi-s3
sleep 3
sudo systemctl is-active fastapi-s3
REMOTE
ok "systemd fastapi-s3 activo"

# ---- 10. Smoke test ---------------------------------------------------------
bold "10. Smoke test desde tu Mac"
sleep 2
HEALTH=$(curl -s -m 8 "http://$PUBLIC_IP:8000/" || echo "FAILED")
echo "  GET http://$PUBLIC_IP:8000/  → $HEALTH"

# ---- Summary ----------------------------------------------------------------
bold "✅ DEPLOY COMPLETO"
cat <<EOF

  Account:           $ACCOUNT_ID
  Region:            $AWS_REGION
  Bucket:            s3://$BUCKET
  IAM policy:        $POLICY_NAME
  IAM role:          $ROLE_NAME
  Instance profile:  $INSTANCE_PROFILE_NAME
  Security group:    $SG_NAME ($SG_ID)
  Key pair:          $KEY_NAME ($KEY_PATH)
  Instance:          $INSTANCE_NAME ($INSTANCE_ID)
  Public IP:         $PUBLIC_IP
  Swagger público:   http://$PUBLIC_IP:8000/docs

  Útiles:
    SSH:             ssh -i $KEY_PATH ec2-user@$PUBLIC_IP
    Logs en vivo:    ssh -i $KEY_PATH ec2-user@$PUBLIC_IP "sudo journalctl -u fastapi-s3 -f"
    Status systemd:  ssh -i $KEY_PATH ec2-user@$PUBLIC_IP "sudo systemctl status fastapi-s3"
    Stop instancia:  aws ec2 stop-instances --instance-ids $INSTANCE_ID
    Terminar:        aws ec2 terminate-instances --instance-ids $INSTANCE_ID

  Ahora abre http://$PUBLIC_IP:8000/docs en el navegador y captura las
  pantallas faltantes (08-13 según la tabla del README).

EOF
