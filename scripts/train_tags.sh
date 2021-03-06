#!/bin/bash

set -e

TF_CPP_MIN_LOG_LEVEL=2
DATA_HOME_DIR=${DATA_HOME_DIR:-/var/lib/ccs/data}
INITIAL_STEPS=${INITIAL_STEPS:-50000}
EVAL_STEPS=${EVAL_STEPS:-5000}
CSV=${CSV:-posts_tags.csv}
PRETRAINED_CHECKPOINT_DIR=$DATA_HOME_DIR/checkpoints
MODEL_DIR=$DATA_HOME_DIR/models
DATASET_DIR=$DATA_HOME_DIR/dataset

for i in "$@"; do
  case $i in
    --data-dir=*)
    DATA_HOME_DIR="${i#*=}"
    shift
    ;;

    --checkpoint-dir=*)
    PRETRAINED_CHECKPOINT_DIR="${i#*=}"
    shift
    ;;

    --model-dir=*)
    MODEL_DIR="${i#*=}"
    shift
    ;;

    --dataset-dir=*)
    DATASET_DIR="${i#*=}"
    shift
    ;;

    *)
    echo "Unknown option: ${i}"
    exit 1
  esac
done

# Download the pre-trained checkpoint.
if [ ! -d "$PRETRAINED_CHECKPOINT_DIR" ]; then
  mkdir ${PRETRAINED_CHECKPOINT_DIR}
fi
if [ ! -f ${PRETRAINED_CHECKPOINT_DIR}/inception_v4.ckpt ]; then
  wget http://download.tensorflow.org/models/inception_v4_2016_09_09.tar.gz
  tar -xvf inception_v4_2016_09_09.tar.gz
  mv inception_v4.ckpt ${PRETRAINED_CHECKPOINT_DIR}/inception_v4.ckpt
  rm inception_v4_2016_09_09.tar.gz
fi

# Download the dataset
slimception/download_and_convert_data.py \
  --dataset_dir=${DATASET_DIR} \
  --num_classes_file=num_tag_classes.txt \
  --num_images_file=num_tag_images.txt \
  --dataset_name=tags \
  --source_csv=${CSV} \
  --multilabel=true

# Fine-tune only the new layers for 1000 steps.
slimception/train_image_classifier.py \
  --train_dir=${MODEL_DIR} \
  --dataset_name=tags \
  --dataset_split_name=train \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --checkpoint_path=${PRETRAINED_CHECKPOINT_DIR}/inception_v4.ckpt \
  --checkpoint_exclude_scopes=InceptionV4/Logits,InceptionV4/AuxLogits \
  --max_number_of_steps=${INITIAL_STEPS} \
  --batch_size=32 \
  --learning_rate=0.04 \
  --learning_rate_decay_type=fixed \
  --save_interval_secs=300 \
  --save_summaries_secs=1800 \
  --log_every_n_steps=100 \
  --optimizer=adam \
  --weight_decay=0.00004 \
  --multilabel=true \
  --label-smoothing=0.1

# Run evaluation.
slimception/eval_image_classifier.py \
  --checkpoint_path=${MODEL_DIR} \
  --eval_dir=${MODEL_DIR} \
  --dataset_name=tags \
  --dataset_split_name=validation \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --multilabel=true

# Fine-tune all the new layers for 500 steps.
slimception/train_image_classifier.py \
  --train_dir=${MODEL_DIR}/all \
  --dataset_name=tags \
  --dataset_split_name=train \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --checkpoint_path=${MODEL_DIR} \
  --max_number_of_steps=${EVAL_STEPS} \
  --batch_size=32 \
  --learning_rate=0.0001 \
  --learning_rate_decay_type=fixed \
  --save_interval_secs=300 \
  --save_summaries_secs=1800 \
  --log_every_n_steps=100 \
  --optimizer=adam \
  --weight_decay=0.00004 \
  --multilabel=true \
  --label-smoothing=0.1

# Run evaluation.
slimception/eval_image_classifier.py \
  --checkpoint_path=${MODEL_DIR}/all \
  --eval_dir=${MODEL_DIR}/all \
  --dataset_name=tags \
  --dataset_split_name=validation \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --multilabel=true
