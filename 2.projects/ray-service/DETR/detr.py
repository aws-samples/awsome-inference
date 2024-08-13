#from transformers import DetrImageProcessor, DetrForObjectDetection
import torch
from PIL import Image
import requests
import tempfile

from ray import serve
# Load model directly
from transformers import AutoImageProcessor, AutoModelForObjectDetection



@serve.deployment()
class ObjectDetection:
    def __init__(self):
        self.processor = AutoImageProcessor.from_pretrained("facebook/detr-resnet-50")
        self.model = AutoModelForObjectDetection.from_pretrained("facebook/detr-resnet-50")


    # Users can send HTTP requests with an image. The detection will return a list of detected objects and their location
    # 
    # Sample output: ["Detected umbrella with confidence 0.997 at location [1098.83, 379.95, 1541.51, 573.64]","Detected person with confidence 1.0 at location [1184.87, 528.97, 1448.08, 1167.76]"]
    
    async def __call__(self, http_request):
        request = await http_request.form()
        image_file = await request["image"].read()

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
            temp_file.write(image_file)
            temp_file.close()
            temp_file_path = temp_file.name
            image = Image.open(temp_file_path)
            #img = image.load_img(temp_file_path, target_size=(224, 224))

        inputs = self.processor(images=image, return_tensors="pt")
        outputs = self.model(**inputs)

        target_sizes = torch.tensor([image.size[::-1]])
        results = self.processor.post_process_object_detection(outputs, target_sizes=target_sizes, threshold=0.9)[0]
        
        result_list = []

        for score, label, box in zip(results["scores"], results["labels"], results["boxes"]):
            box = [round(i, 2) for i in box.tolist()]
            result_list.append(f"Detected {self.model.config.id2label[label.item()]} with confidence {round(score.item(), 3)} at location {box}")

        return result_list


app = ObjectDetection.bind()
