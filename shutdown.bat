@echo off

kubectl delete -f deployment.yaml

echo Looking for container with image registry:2...

REM Get the container ID of the registry:2 container
for /f "tokens=*" %%i in ('docker ps --filter "ancestor=registry:2" --format "{{.ID}}"') do (
	echo Found container: %%i
	echo Stopping container...
	docker stop %%i
	if errorlevel 1 (
		echo Error stopping container
		exit /b 1
	) else (
		echo Container stopped successfully
	)
	goto :done
)

echo No running container found with image registry:2

:done

REM Remove all local images that were pushed to the temporary registry
echo Removing local temporary registry images...
docker rmi localhost:5000/mnist-predictor-server
docker rmi localhost:5000/mnist-predictor-model-loader
docker rmi localhost:5000/mnist-predictor-worker

pause
exit /b 0