import sys
import os
sys.path.append(os.path.normpath(os.path.join(__file__, "..", "..")))

from flask import Flask
from flask import request, render_template, redirect, url_for
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
import json
import re
import numpy as np
import tensorflow as tf
from slimception.datasets import characters
from slimception.preprocessing import preprocessing_factory
from slimception.nets import nets_factory
from slimception.datasets import dataset_factory

slim = tf.contrib.slim
_dotenv_path = "/etc/ccs/env"
load_dotenv(_dotenv_path)
ACCESS_KEY = os.environ.get("ACCESS_KEY")
ACCESS_SECRET = os.environ.get("ACCESS_SECRET")
FILE_UPLOAD_DIR = os.environ.get("FILE_UPLOAD_DIR")
DATASET_DIR = os.environ.get("DATASET_DIR") # FLAGS.dataset_dir
CHECKPOINTS_DIR = os.environ.get("CHECKPOINTS_DIR") # FLAGS.checkpoints_dir
ALLOWED_EXTENSIONS = set(["jpg", "jpeg", "png"])
_reuse = False

with open(os.path.join(DATASET_DIR, "labels.txt"), "r") as f:
  _labels = [re.sub(r"^\d+:", "", x) for x in f.read().split()]

def allowed_file(filename):
  return '.' in filename and \
    filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def query_inception(file):
  with tf.Graph().as_default():
    dataset = dataset_factory.get_dataset(
      "characters", 
      "validation",
      DATASET_DIR
    )
    image_processing_fn = preprocessing_factory.get_preprocessing(
      "inception_v4",
      is_training=False
    )
    image = tf.image.decode_image(file.read(), channels=3)
    network_fn = nets_factory.get_network_fn(
      "inception_v4", 
      num_classes=dataset.num_classes,
      is_training=False,
      reuse=_reuse
    )
    eval_image_size = network_fn.default_image_size
    processed_image = image_processing_fn(image, eval_image_size, eval_image_size)
    processed_images = tf.expand_dims(processed_image, 0)
    logits, _ = network_fn(processed_images)
    probabilities = tf.nn.softmax(logits)
    checkpoint_path = tf.train.latest_checkpoint(CHECKPOINTS_DIR)
    variables_to_restore = slim.get_variables_to_restore()
    init_fn = slim.assign_from_checkpoint_fn(checkpoint_path, variables_to_restore)

    with tf.Session() as sess:
      init_fn(sess)
      np_image, network_input, probabilities = sess.run([image, processed_image, probabilities])
      _reuse = True
      probabilities = probabilities[0, 0:]
      return sorted(zip(probabilities, _labels), reverse=True)[0:3]

app = Flask("ccs")
app.config["UPLOAD_FOLDER"] = FILE_UPLOAD_DIR

@app.route("/")
def index():
  return redirect(url_for("query"))

@app.route("/query", methods=["GET", "POST"])
def query():
  if request.method == "POST":
    # access_key = request.form["access_key"]
    # access_secret = request.form["access_secret"]
    # if access_key != ACCESS_KEY and access_secret != ACCESS_SECRET:
    #   abort(403)
    if "file" not in request.files:
      flash("No file uploaded")
      return redirect(request.url)
    f = request.files["file"]
    if f.filename == '':
      flash("No file uploaded")
      return redirect(request.url)
    if f and allowed_file(f.filename):
      return json.dumps(query_inception(f))
    else:
      flash("Content type not supported")
      return redirect(request.url)
  else:
    return render_template("upload.html")

if __name__ == "__main__":
  app.run(debug=False, host="0.0.0.0")
