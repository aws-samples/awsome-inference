# from flask import Flask, jsonify

# app = Flask(__name__)

# @app.route('/healthz', methods=['GET'])
# def healthcheck():
#     """
#     Health check endpoint.
#     Returns a JSON response with a 'status' field set to 'OK' when the server is healthy.
#     """
#     return jsonify({'status': 'OK'})

# if __name__ == '__main__':
#     app.run(host='0.0.0.0', port=8000, debug=False)
import http.server
import socketserver

PORT = 8080

Handler = http.server.SimpleHTTPRequestHandler

class HealthcheckHandler(Handler):
    def do_GET(self):
        if self.path == '/healthz':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')            
        else:
            return Handler.do_GET(self)

with socketserver.TCPServer(("", PORT), HealthcheckHandler) as httpd:
    print("serving at port", PORT)
    httpd.serve_forever()            