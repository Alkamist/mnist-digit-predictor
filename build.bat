@echo off

docker build -t alkamist1/digit-image-predictor:server-0.1.0 ./server
docker tag alkamist1/digit-image-predictor:server-0.1.0 alkamist1/digit-image-predictor:server-latest

docker build -t alkamist1/digit-image-predictor:worker-0.1.0 ./worker
docker tag alkamist1/digit-image-predictor:worker-0.1.0 alkamist1/digit-image-predictor:worker-latest

docker push alkamist1/digit-image-predictor:server-0.1.0
docker push alkamist1/digit-image-predictor:worker-0.1.0

pause