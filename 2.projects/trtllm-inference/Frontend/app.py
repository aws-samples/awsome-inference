from flask import Flask, render_template, request, session
import requests
import os
import time
import markdown2

SECRET_KEY = os.urandom(24)

app = Flask(__name__)
app.config['SECRET_KEY'] = SECRET_KEY

@app.route('/', methods=['GET', 'POST'])

def index():
    if request.method == 'POST':
        try:
            prompt = request.form['prompt']    
            max_tokens = int(request.form['max-tokens'])
            bad_words = request.form.getlist('bad-words')
            stop_words = request.form.getlist('stop-words')       

            # Capture the start time
            start_time = time.time()

            response = requests.post('http://k8s-default-trtllmin-2449f615fc-1027553759.us-east-2.elb.amazonaws.com/v2/models/ensemble/generate', 
                                    json={
                                        "text_input": prompt,
                                        "max_tokens": max_tokens,
                                        "bad_words": ",".join(bad_words),
                                        "stop_words": ",".join(stop_words)     
                                        }
                                    )
            response.raise_for_status()
            result=markdown2.markdown(response.json()['text_output'])
            total_tokens = len(response.json()['output_log_probs'])

            # Calculate the latency
            latency = time.time() - start_time
            tokens_per_second = total_tokens / latency

            # Fetch the token count from the /metrics endpoint
            metrics_response = requests.get('http://k8s-default-trtllmin-2449f615fc-1027553759.us-east-2.elb.amazonaws.com/metrics')
            metrics_response.raise_for_status()
            token_count = parse_token_count(metrics_response.text)

            # Storing prompt + result from session
            if 'history' not in session:
                session['history'] = []
            session['history'].insert(0, {'prompt': prompt, 'result': result, 'latency': f"{latency:.2f} seconds", "token_count": token_count, "total_tokens": total_tokens, "tokens_per_second": f"{tokens_per_second:.2f}"})    

            return render_template('index.html', prompt=prompt, result=result, history=session['history'])
        except requests.exceptions.RequestException as e:
            return render_template('index.html', error=str(e), history=session.get('history', []))
    return render_template('index.html', history=session.get('history', []))

def parse_token_count(metrics_text):
    for line in metrics_text.split('\n'):
        if 'nv_trt_llm_kv_cache_block_metrics{kv_cache_block_type="tokens_per",model="tensorrt_llm",version="1"}' in line:
            return int(line.split(' ')[-1])
    return 'N/A'

@app.route('/healthcheck', methods=['GET'])
def healthcheck():
    # Perform any necessary health checks here
    # For example, you can check the status of your database connection
    return 'OK', 200

if __name__ == '__main__':
    app.run(debug=True)

