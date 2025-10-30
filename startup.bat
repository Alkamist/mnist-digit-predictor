@echo off

docker run -d -p 5000:5000 registry:2

timeout /t 2 /nobreak

cd mnist-predictor-server
docker build -t localhost:5000/mnist-predictor-server .
cd ..

cd mnist-predictor-worker
docker build -f Dockerfile.model-loader -t localhost:5000/mnist-predictor-model-loader .
docker build -f Dockerfile.worker -t localhost:5000/mnist-predictor-worker .
cd ..

docker push localhost:5000/mnist-predictor-server
docker push localhost:5000/mnist-predictor-model-loader
docker push localhost:5000/mnist-predictor-worker

kubectl apply -f deployment.yaml

timeout /t 10 /nobreak

kubectl port-forward service/mnist-predictor-server-service 8080:80

pause