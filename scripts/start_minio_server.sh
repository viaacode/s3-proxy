echo "MINIO HTTP TRACE TURNED ON FOR DEBUGGING. WATCH LOGS BY LOGGING IN:"
echo "docker exec -it minio1 /bin/sh"
echo "tail -f minio_server.log"
echo ""


echo "Downloading new minio images if necessary..."
docker pull minio/minio
echo "done"

echo "Stopping and removing old minio container..."
docker stop minio1
docker rm minio1
echo "done"

echo "Starting minio server && storing files in ~/minio_data and ~/minio_config ..."
mkdir -p minio_config
mkdir -p minio_data

DATA_DIR="$PWD/minio_data"
CONFIG_DIR="$PWD/minio_config"

docker run -p 9999:9000 --name minio1 \
  -e "MINIO_ACCESS_KEY=TOPSECRET" \
  -e "MINIO_SECRET_KEY=ViaaSecret2019/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  -e "MINIO_HTTP_TRACE=minio_server.log" \
  -v $DATA_DIR:/data \
  -v $CONFIG_DIR:/root/.minio \
  minio/minio server /data



