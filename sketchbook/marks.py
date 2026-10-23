"""marks.py <photo> [cat]: face boxes and eyes as mosaic_faces.py's BOXES and EYES, from OpenCV's Haar
cascades (people: frontal face + eyes; cats: frontalcatface), standing in for the app's Vision."""
import sys, cv2
p = sys.argv[1]; cat = len(sys.argv) > 2 and sys.argv[2] == "cat"
g = cv2.equalizeHist(cv2.cvtColor(cv2.imread(p), cv2.COLOR_BGR2GRAY))
d = cv2.data.haarcascades
fc = cv2.CascadeClassifier(d + ("haarcascade_frontalcatface_extended.xml" if cat else "haarcascade_frontalface_default.xml"))
faces = sorted(fc.detectMultiScale(g, 1.05, 4, minSize=(60, 60)), key=lambda f: -f[2] * f[3])[:1]
boxes, eyes = [], []
ec = cv2.CascadeClassifier(d + "haarcascade_eye.xml")
for x, y, w, h in faces:
    m = 0.15
    boxes.append(f"{max(0,int(x-m*w))},{max(0,int(y-m*h))},{int(x+w*(1+m))},{int(y+h*(1+m))}")
    es = ec.detectMultiScale(g[y:y + h // 2 + h // 6, x:x + w], 1.05, 6, minSize=(w // 10, w // 10))
    es = sorted(es, key=lambda e: -e[2])[:2]
    for ex, ey, ew, eh in es:
        eyes.append(f"{x+ex+ew//2},{y+ey+eh//2},{int(ew*0.11)}")
print(";".join(boxes)); print(";".join(eyes))
