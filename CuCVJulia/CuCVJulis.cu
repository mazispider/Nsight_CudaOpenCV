#include<iostream>
#include<cstdio>
#include<opencv2/core/core.hpp>
#include<opencv2/highgui/highgui.hpp>
#include<cuda_runtime.h>

using std::cout;
using std::endl;

static inline void _safe_cuda_call(cudaError err, const char* msg, const char* file_name, const int line_number)
{
	if (err != cudaSuccess)
	{
		fprintf(stderr, "%s\n\nFile: %s\n\nLine Number: %d\n\nReason: %s\n", msg, file_name, line_number, cudaGetErrorString(err));
		std::cin.get();
		exit(EXIT_FAILURE);
	}
}

#define SAFE_CALL(call,msg) _safe_cuda_call((call),(msg),__FILE__,__LINE__)
#define DIM 8192

struct cuComplex {
	float   r;
	float   i;
	// cuComplex( float a, float b ) : r(a), i(b)  {}
	__device__ cuComplex(float a, float b) : r(a), i(b) {} // Fix error for calling host function from device
	__device__ float magnitude2(void) {
		return r * r + i * i;
	}
	__device__ cuComplex operator*(const cuComplex& a) {
		return cuComplex(r*a.r - i * a.i, i*a.r + r * a.i);
	}
	__device__ cuComplex operator+(const cuComplex& a) {
		return cuComplex(r + a.r, i + a.i);
	}
};

__device__ int julia(int x, int y) {
	const float scale = 1.5;
	float jx = scale * (float)(DIM / 2 - x) / (DIM / 2);
	float jy = scale * (float)(DIM / 2 - y) / (DIM / 2);

	cuComplex c(-0.8, 0.156);
	cuComplex a(jx, jy);

	int i = 0;
	for (i = 0; i<200; i++) {
		a = a * a + c;
		if (a.magnitude2() > 1000)
			return 0;
	}

	return 1;
}

__global__ void kernel(unsigned char *ptr) {
	// map from blockIdx to pixel position
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	int offset = x + y * DIM;

	// now calculate the value at that position
	if (x < DIM || y < DIM) {
		int juliaValue = julia(x, y);
		ptr[offset*3] = 0;
		ptr[offset*3 + 1] = 0;
		ptr[offset*3 + 2] = 255 * juliaValue;
	}
}

void julia(cv::Mat& output)
{
	//Calculate total number of bytes of input and output image

	const int grayBytes = output.step * output.rows;

	unsigned char  *d_output;
	std::cout << grayBytes << std::endl;
	//Allocate device memory
	SAFE_CALL(cudaMalloc<unsigned char>(&d_output, grayBytes), "CUDA Malloc Failed");

	//Copy data from OpenCV input image to device memory


	//Specify a reasonable block size
	const dim3 block(16, 16);

	//Calculate grid size to cover the whole image
	const dim3 grid((output.cols + block.x - 1) / block.x, (output.rows + block.y - 1) / block.y);

	//Launch the color conversion kernel
	kernel <<<grid, block >>>(d_output);

	//Synchronize to check for any kernel launch errors
	SAFE_CALL(cudaDeviceSynchronize(), "Kernel Launch Failed");

	//Copy back data from destination device meory to OpenCV output image
	SAFE_CALL(cudaMemcpy(output.ptr(), d_output, grayBytes, cudaMemcpyDeviceToHost), "CUDA Memcpy Host To Device Failed");

	//Free the device memory
	SAFE_CALL(cudaFree(d_output), "CUDA Free Failed");
}

int main()
{
	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);



	//Create output image
	cv::Mat output(DIM, DIM, CV_8UC3);
	std::cout << output.cols << std::endl;
	cudaEventRecord(start,0);
	//Call the wrapper function
	julia(output);
	cudaEventRecord(stop,0);
	cudaEventSynchronize(stop);
	float   elapsedTime;
	cudaEventElapsedTime(&elapsedTime, start, stop);
	std::cout << "time to generate " << 1000 * elapsedTime << "us." << std::endl;
	//Show the input and output
	//cv::imshow("Input", input);
	//cv::imshow("Output", output);
	cv::imwrite("./julia.jpg", output);
	//Wait for key press
	cv::waitKey();
	std::cin.get();
	return 0;
}
