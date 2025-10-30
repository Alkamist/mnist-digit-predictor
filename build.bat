@echo off

docker build -t alkamist1/digit-image-predictor:server-0.1.2 ./server
docker build -t alkamist1/digit-image-predictor:worker-0.1.2 ./worker

pause