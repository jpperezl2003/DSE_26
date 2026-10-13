"""Ejecutar con Python 3.12+ antes de terraform plan."""
import pathlib
import subprocess
import sys
import tempfile
import zipfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
(ROOT / "build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="lambda-", dir=ROOT / "build") as temp:
    cert = pathlib.Path(temp) / "rds-ca.pem"
    urllib.request.urlretrieve("https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem", cert)
    subprocess.run([
        sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
        "--platform", "manylinux2014_x86_64", "--python-version", "3.12",
        "--implementation", "cp", "--only-binary=:all:",
        "-r", str(ROOT / "requirements.txt"), "--target", temp,
    ], check=True)
    with zipfile.ZipFile(ROOT / "build/lambda.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(pathlib.Path(temp).rglob("*")):
            if file.is_file() and "__pycache__" not in file.parts:
                archive.write(file, file.relative_to(temp).as_posix())
        archive.write(ROOT / "app.py", "app.py")
        archive.write(ROOT / "seed.sql", "seed.sql")
print("Creado build/lambda.zip")
