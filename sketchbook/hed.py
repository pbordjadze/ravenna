# Runs paint-by-number's convert_hed.py with MediaPipe hidden: controlnet_aux reaches for the legacy
# mediapipe.solutions when mediapipe is installed, and the installed one (for features.py) has none.
import runpy, sys
sys.modules["mediapipe"] = None
sys.argv = [sys.argv[1]] + sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")
