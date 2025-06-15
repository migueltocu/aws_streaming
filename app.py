from flask import Flask, request, jsonify, render_template
from datetime import datetime
import json

app = Flask(__name__)

# Lista para almacenar mensajes recibidos (en memoria)
messages = []

@app.route('/')
def home():
    """Renderizar la página principal HTML"""
    return render_template('index.html')

@app.route('/api')
def api_info():
    """Endpoint básico de información de la API"""
    return jsonify({
        "message": "API de Streaming funcionando",
        "timestamp": datetime.now().isoformat(),
        "status": "OK"
    })

@app.route('/health', methods=['GET'])
def health_check():
    """Endpoint de health check"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "messages_count": len(messages)
    })

@app.route('/messages', methods=['POST'])
def receive_message():
    """Endpoint para recibir mensajes del generador"""
    try:
        # Obtener datos del request
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "No se recibieron datos"}), 400
        
        # Agregar timestamp al mensaje
        message = {
            "data": data,
            "received_at": datetime.now().isoformat(),
            "id": len(messages) + 1
        }
        
        # Almacenar mensaje
        messages.append(message)
        
        # Log para debugging
        print(f"Mensaje recibido: {json.dumps(message, indent=2)}")
        
        return jsonify({
            "status": "success",
            "message": "Mensaje recibido correctamente",
            "message_id": message["id"]
        }), 201
        
    except Exception as e:
        print(f"Error procesando mensaje: {str(e)}")
        return jsonify({"error": "Error interno del servidor"}), 500

@app.route('/messages', methods=['GET'])
def get_messages():
    """Endpoint para obtener todos los mensajes recibidos"""
    return jsonify({
        "messages": messages,
        "count": len(messages),
        "timestamp": datetime.now().isoformat()
    })

@app.route('/messages/<int:message_id>', methods=['GET'])
def get_message(message_id):
    """Endpoint para obtener un mensaje específico por ID"""
    message = next((m for m in messages if m["id"] == message_id), None)
    
    if not message:
        return jsonify({"error": "Mensaje no encontrado"}), 404
    
    return jsonify(message)

@app.route('/messages/clear', methods=['DELETE'])
def clear_messages():
    """Endpoint para limpiar todos los mensajes"""
    global messages
    count = len(messages)
    messages = []
    
    return jsonify({
        "status": "success",
        "message": f"Se eliminaron {count} mensajes",
        "timestamp": datetime.now().isoformat()
    })

@app.errorhandler(404)
def not_found(error):
    """Manejador de errores 404"""
    return jsonify({"error": "Endpoint no encontrado"}), 404

@app.errorhandler(500)
def internal_error(error):
    """Manejador de errores 500"""
    return jsonify({"error": "Error interno del servidor"}), 500

if __name__ == '__main__':
    print("Iniciando API Flask...")
    print("Endpoints disponibles:")
    print("  GET  /              - Página principal HTML")
    print("  GET  /api           - Información de la API")
    print("  GET  /health        - Health check")
    print("  POST /messages      - Recibir mensajes")
    print("  GET  /messages      - Obtener todos los mensajes")
    print("  GET  /messages/<id> - Obtener mensaje específico")
    print("  DELETE /messages/clear - Limpiar mensajes")
    print("\nAccede a http://localhost:5000 para ver el dashboard")
    
    # Ejecutar en modo debug para desarrollo
    app.run(debug=True, host='0.0.0.0', port=5000)