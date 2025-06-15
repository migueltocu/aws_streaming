# Usar imagen base de Python
FROM python:3.9-slim

# Establecer directorio de trabajo
WORKDIR /app

# Copiar archivos de dependencias
COPY requirements.txt .

# Instalar dependencias
RUN pip install --no-cache-dir -r requirements.txt

# Copiar c�digo de la aplicaci�n
COPY . .

# Exponer puerto
EXPOSE 5000

# Variables de entorno para Flask
ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0
ENV FLASK_RUN_PORT=5000

# Comando para ejecutar la aplicaci�n
CMD ["python", "app.py"]