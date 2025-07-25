from sglang import function, system, user, assistant, gen, set_default_backend, RuntimeEndpoint
import time

@function
def multi_turn_question(s, question_1):
    s += system("You are a helpful assistant.")
    s += user(question_1)
    s += assistant(gen("answer_1", max_tokens=256))

set_default_backend(RuntimeEndpoint("http://44.251.237.226:8000"))

latencies = []
while True:
    try:
        start_time = time.time()
        
        state = multi_turn_question.run(
            question_1="What is the capital of the United States?",
        )
        
        for m in state.messages():
            role, content = m["role"], m["content"]
            print(f"{role}: {content}")
            
        end_time = time.time()
        latency = end_time - start_time
        latencies.append(latency)
        
        # Calculate and display running average
        avg_latency = sum(latencies) / len(latencies)
        print(f"\rLatest: {latency:.3f}s, Average: {avg_latency:.3f}s", end="", flush=True)
    except KeyboardInterrupt:
        print("\nExiting...")
        break
    except Exception as e:
        print(f"Error occurred: {e}")
        continue
