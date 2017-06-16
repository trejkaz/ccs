#!/bin/bash

set -e

DATA_HOME_DIR=~/tf-data
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
  --dataset_dir=${DATASET_DIR}

# Fine-tune only the new layers for 1000 steps.
slimception/train_image_classifier.py \
  --MODEL_DIR=${MODEL_DIR} \
  --dataset_name=characters \
  --dataset_split_name=train \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --checkpoint_path=${PRETRAINED_CHECKPOINT_DIR}/inception_v4.ckpt \
  --checkpoint_exclude_scopes=InceptionV4/Logits,InceptionV4/AuxLogits \
  --max_number_of_steps=15000 \
  --batch_size=32 \
  --learning_rate=0.02 \
  --learning_rate_decay_type=fixed \
  --save_interval_secs=60 \
  --save_summaries_secs=60 \
  --log_every_n_steps=250 \
  --optimizer=adam \
  --weight_decay=0.00004

# Run evaluation.
slimception/eval_image_classifier.py \
  --checkpoint_path=${MODEL_DIR} \
  --eval_dir=${MODEL_DIR} \
  --dataset_name=characters \
  --dataset_split_name=validation \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4

# Fine-tune all the new layers for 500 steps.
slimception/train_image_classifier.py \
  --MODEL_DIR=${MODEL_DIR}/all \
  --dataset_name=characters \
  --dataset_split_name=train \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4 \
  --checkpoint_path=${MODEL_DIR} \
  --max_number_of_steps=4000 \
  --batch_size=32 \
  --learning_rate=0.0001 \
  --learning_rate_decay_type=fixed \
  --save_interval_secs=60 \
  --save_summaries_secs=60 \
  --log_every_n_steps=10 \
  --optimizer=adam \
  --weight_decay=0.00004

# Run evaluation.
slimception/eval_image_classifier.py \
  --checkpoint_path=${MODEL_DIR}/all \
  --eval_dir=${MODEL_DIR}/all \
  --dataset_name=characters \
  --dataset_split_name=validation \
  --dataset_dir=${DATASET_DIR} \
  --model_name=inception_v4
