//****************************************************************************
// Also note that we've supplied a helpful debugging function called checkCudaErrors.
// You should wrap your allocation and copying statements like we've done in the
// code we're supplying you. Here is an example of the unsafe way to allocate
// memory on the GPU:
//
// cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols);
//
// Here is an example of the safe way to do the same thing:
//
// checkCudaErrors(cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols));
//****************************************************************************

#include <iostream>
#include <iomanip>
#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>

#define checkCudaErrors(val) check( (val), #val, __FILE__, __LINE__)

#define BLOCK_SIZE 32
#define FILTER_WIDTH 5
#define clamp(x) (min(max((x), 0.0), 1.0))

template<typename T>
void check(T err, const char* const func, const char* const file, const int line) {
	if (err != cudaSuccess) {
		std::cerr << "CUDA error at: " << file << ":" << line << std::endl;
		std::cerr << cudaGetErrorString(err) << " " << func << std::endl;
		exit(1);
	}
}

// Optimize for pointer aliasing using __restrict__ allows CUDA commpiler to use the read-only data cache and improves performance
__global__
//void box_filter(const unsigned char* const inputChannel, unsigned char* const outputChannel, int numRows, int numCols, const float* __restrict__ filter, const int filterWidth)
void box_filter(const unsigned char* const inputChannel, unsigned char* const outputChannel, int numRows, int numCols, const float* filter, const int filterWidth)
{
	// NOTA: Que un thread tenga una posici�n correcta en 2D no quiere decir que al aplicar el filtro
	// los valores de sus vecinos sean correctos, ya que pueden salirse de la imagen.

	const unsigned int x0 = threadIdx.x;
	const unsigned int y0 = threadIdx.y;

	/// which thread is this?
	const int tx = blockIdx.x*blockDim.x + x0;
	const int ty = blockIdx.y*blockDim.y + y0;

	/// if thread is out the image
	if (tx >= numCols || ty >= numRows)
		return;

	const int filterRadius = FILTER_WIDTH / 2;
	float value = 0.0f;
	
	/// Share memory - Input tiles need to be larger than output tiles
	__shared__ float ds_inputChannel[BLOCK_SIZE+FILTER_WIDTH-1][BLOCK_SIZE+FILTER_WIDTH-1];
	////Each thread copy the vertex of the filter, the 4 corners - error some pixels
	int fx, fy; // Index for the filter corners
	// case1: upper left
	fx = tx - filterRadius;
	fy = ty - filterRadius;
	if (fx < 0 || fy < 0)
		ds_inputChannel[x0][y0] = 0.0f;
	else
		ds_inputChannel[x0][y0] = inputChannel[ty*numCols + tx - filterRadius - numCols];

	// case2: upper right
	fx = tx + filterRadius;
	fy = ty - filterRadius;
	if (fx > numCols-1 || fy < 0)
		ds_inputChannel[x0 + FILTER_WIDTH][y0] = 0.0f;
	else
		ds_inputChannel[x0 + FILTER_WIDTH][y0] = inputChannel[ty*numCols + tx + filterRadius - numCols];

	// case3: lower left
	fx = tx - filterRadius;
	fy = ty + filterRadius;
	if (fx < 0 || fy > numRows-1)
		ds_inputChannel[x0][y0 + FILTER_WIDTH] = 0.0f;
	else
		ds_inputChannel[x0][y0 + FILTER_WIDTH] = inputChannel[ty*numCols + tx - filterRadius + numCols];

	// case4: lower right
	fx = tx + filterRadius;
	fy = ty + filterRadius;
	if (fx > numCols - 1 || fy > numRows-1)
		ds_inputChannel[x0 + FILTER_WIDTH][y0 + FILTER_WIDTH] = 0.0f;
	else
		ds_inputChannel[x0 + FILTER_WIDTH][y0 + FILTER_WIDTH] = inputChannel[ty*numCols + tx + filterRadius + numCols];

	__syncthreads(); // SyncThreads to have all the share memory complete

	for (int i = 0; i < FILTER_WIDTH; ++i){
		for (int j = 0; j < FILTER_WIDTH; ++j){
			value += filter[j*filterWidth + i] * ds_inputChannel[x0 + i][y0 + j];
		}
	}

	///Share memory, block memory are BLOCK_SIZE
	//__shared__ float ds_inputChannel[BLOCK_SIZE][BLOCK_SIZE];
	/////Each thread copy his pixel to the share memory - inefficient, we have to access to global memory at borders and corners
	//ds_inputChannel[y0][x0] = inputChannel[ty*numCols + tx];
	//for (int i = 0; i < FILTER_WIDTH; ++i){
	//	/// which pixel is?
	//	//int fx = blockIdx.x*blockDim.x + (threadIdx.x + i - filterRadius);
	//	int fx = blockIdx.x*blockDim.x + (threadIdx.x + i - filterRadius);
	//	int fsx = x0 + i - filterRadius;
	//	/// Clamp of neighbourds values
	//	if (fx < 0)  fx = 0;
	//	if (fx > numCols - 1)  fx = numCols - 1;

	//	for (int j = 0; j < FILTER_WIDTH; ++j){
	//		/// which pixel is?
	//		int fy = blockIdx.y*blockDim.y + (threadIdx.y + j - filterRadius);
	//		int fsy = y0 + j - filterRadius;
	//		/// Clamp of neighbourds values
	//		if (fy < 0)  fy = 0;
	//		if (fy > numRows - 1)  fy = numRows - 1;
	//		/// Compute the value at the pixel and add it - Inefficient, access to global memory and if-else.
	//		if ((fsx >= 0) && (fsy >= 0) && (fsx <= BLOCK_SIZE - 1) && (fsy <= BLOCK_SIZE - 1))
	//			value += filter[j*filterWidth + i] * ds_inputChannel[fsy][fsx];
	//		else
	//			value += filter[j*filterWidth + i] * inputChannel[fy*numCols + fx];
	//	}
	//}

	// Whitout share memory
	/*for (int i = 0; i < filterWidth; ++i){
		/// which pixel is?
		int fx = blockIdx.x*blockDim.x + (threadIdx.x + i - filterRadius);
		/// Clamp of neighbourds values
		if (fx < 0)  fx = 0;
		if (fx > numCols - 1)  fx = numCols - 1;

		for (int j = 0; j < filterWidth; ++j){
			/// which pixel is?
			int fy = blockIdx.y*blockDim.y + (threadIdx.y + j - filterRadius);
			/// Clamp of neighbourds values
			if (fy < 0)  fy = 0;
			if (fy > numRows - 1)  fy = numRows - 1;
			/// Compute the value at the pixel and add it.
			value += filter[j*filterWidth + i] * inputChannel[fy*numCols + fx];
		}
	}*/

	/// Save the value at the outputChanel
	outputChannel[ty*numCols + tx] = value;
}

//This kernel takes in an image represented as a uchar4 and splits
//it into three images consisting of only one color channel each
__global__
void separateChannels(const uchar4* const inputImageRGBA,
int numRows,
int numCols,
unsigned char* const redChannel,
unsigned char* const greenChannel,
unsigned char* const blueChannel)
{
	/// which thread is this?
	const int tx = blockIdx.x*blockDim.x + threadIdx.x;
	const int ty = blockIdx.y*blockDim.y + threadIdx.y;

	/// if thread is out the image
	if (tx >= numCols || ty >= numRows)
		return;

	/// Index to get the array position
	const int index = ty * numCols + tx;

	/// split colors
	redChannel[index] = inputImageRGBA[index].x;
	greenChannel[index] = inputImageRGBA[index].y;
	blueChannel[index] = inputImageRGBA[index].z;

}

//This kernel takes in three color channels and recombines them
//into one image. The alpha channel is set to 255 to represent
//that this image has no transparency.
__global__
void recombineChannels(const unsigned char* const redChannel,
const unsigned char* const greenChannel,
const unsigned char* const blueChannel,
uchar4* const outputImageRGBA,
int numRows,
int numCols)
{
	const int2 thread_2D_pos = make_int2(blockIdx.x * blockDim.x + threadIdx.x,
		blockIdx.y * blockDim.y + threadIdx.y);

	const int thread_1D_pos = thread_2D_pos.y * numCols + thread_2D_pos.x;

	//make sure we don't try and access memory outside the image
	//by having any threads mapped there return early
	if (thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows)
		return;

	unsigned char red = redChannel[thread_1D_pos];
	unsigned char green = greenChannel[thread_1D_pos];
	unsigned char blue = blueChannel[thread_1D_pos];

	//Alpha should be 255 for no transparency
	uchar4 outputPixel = make_uchar4(red, green, blue, 255);

	outputImageRGBA[thread_1D_pos] = outputPixel;
}

unsigned char *d_red, *d_green, *d_blue;
float         *d_filter;
//__constant__ float d_filter[FILTER_WIDTH*FILTER_WIDTH];
//__constant__ float *d_filter;

void allocateMemoryAndCopyToGPU(const size_t numRowsImage, const size_t numColsImage,
	const float* const h_filter, const size_t filterWidth)
{

	//allocate memory for the three different channels
	checkCudaErrors(cudaMalloc(&d_red, sizeof(unsigned char) * numRowsImage * numColsImage));
	checkCudaErrors(cudaMalloc(&d_green, sizeof(unsigned char) * numRowsImage * numColsImage));
	checkCudaErrors(cudaMalloc(&d_blue, sizeof(unsigned char) * numRowsImage * numColsImage));

	//Reservar memoria para el filtro en GPU: d_filter, la cual ya esta declarada
	// Copiar el filtro  (h_filter) a memoria global de la GPU (d_filter)
	checkCudaErrors(cudaMalloc(&d_filter, sizeof(float)*filterWidth*filterWidth));
	checkCudaErrors(cudaMemcpy(d_filter, h_filter, sizeof(float)*filterWidth*filterWidth, cudaMemcpyHostToDevice));
	//checkCudaErrors(cudaMemcpyToSymbol(d_filter, h_filter, sizeof(float)*filterWidth*filterWidth));
}


void create_filter(float **h_filter, int *filterWidth){

	const int KernelWidth = 5; //OJO CON EL TAMA�O DEL FILTRO//
	//printf("%d\n",KernelWidth);
	//const int KernelWidth = 3;
	*filterWidth = KernelWidth;

	//create and fill the filter we will convolve with
	*h_filter = new float[KernelWidth * KernelWidth];

	/*
	//Filtro gaussiano: blur
	const float KernelSigma = 2.;

	float filterSum = 0.f; //for normalization

	for (int r = -KernelWidth/2; r <= KernelWidth/2; ++r) {
	for (int c = -KernelWidth/2; c <= KernelWidth/2; ++c) {
	float filterValue = expf( -(float)(c * c + r * r) / (2.f * KernelSigma * KernelSigma));
	(*h_filter)[(r + KernelWidth/2) * KernelWidth + c + KernelWidth/2] = filterValue;
	filterSum += filterValue;
	}
	}

	float normalizationFactor = 1.f / filterSum;

	for (int r = -KernelWidth/2; r <= KernelWidth/2; ++r) {
	for (int c = -KernelWidth/2; c <= KernelWidth/2; ++c) {
	(*h_filter)[(r + KernelWidth/2) * KernelWidth + c + KernelWidth/2] *= normalizationFactor;
	}
	}
	*/

	//Laplaciano 5x5
	(*h_filter)[0] = 0;   (*h_filter)[1] = 0;    (*h_filter)[2] = -1.;  (*h_filter)[3] = 0;    (*h_filter)[4] = 0;
	(*h_filter)[5] = 1.;  (*h_filter)[6] = -1.;  (*h_filter)[7] = -2.;  (*h_filter)[8] = -1.;  (*h_filter)[9] = 0;
	(*h_filter)[10] = -1.; (*h_filter)[11] = -2.; (*h_filter)[12] = 17.; (*h_filter)[13] = -2.; (*h_filter)[14] = -1.;
	(*h_filter)[15] = 1.; (*h_filter)[16] = -1.; (*h_filter)[17] = -2.; (*h_filter)[18] = -1.; (*h_filter)[19] = 0;
	(*h_filter)[20] = 0;  (*h_filter)[21] = 0;   (*h_filter)[22] = -1.; (*h_filter)[23] = 0;   (*h_filter)[24] = 0;

	//Crear los filtros segun necesidad
	//NOTA: cuidado al establecer el tama�o del filtro a utilizar

	//////// FILTROS DE NITIDEZ
	///Nitidez 5x5 - kernelWidth = 5
	//(*h_filter)[0] = 0;		(*h_filter)[1] = -1.;	(*h_filter)[2] = -1.;  (*h_filter)[3] = -1.;	(*h_filter)[4] = 0;
	//(*h_filter)[5] = -1.;	(*h_filter)[6] = 2.;	(*h_filter)[7] = -4.;  (*h_filter)[8] = 2.;		(*h_filter)[9] = -1.;
	//(*h_filter)[10] = -1.;	(*h_filter)[11] = -4.;	(*h_filter)[12] = 13.; (*h_filter)[13] = -4.;	(*h_filter)[14] = -1.;
	//(*h_filter)[15] = -1.;	(*h_filter)[16] = 2.;	(*h_filter)[17] = -4.; (*h_filter)[18] = 2.;	(*h_filter)[19] = -1.;
	//(*h_filter)[20] = 0;	(*h_filter)[21] = -1.;  (*h_filter)[22] = -1.; (*h_filter)[23] = -1.;   (*h_filter)[24] = 0;

	/// Nitidez 3x3
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = -1.;  
	//(*h_filter)[3] = -1.;	(*h_filter)[4] = 9.;	(*h_filter)[5] = -1.;	
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = -1.;	(*h_filter)[8] = -1.;

	/// Aumentar nitidez
	//(*h_filter)[0] = 0.;	(*h_filter)[1] = -0.25;	(*h_filter)[2] = 0.;
	//(*h_filter)[3] = -0.25;	(*h_filter)[4] = 2.;	(*h_filter)[5] = -0.25;
	//(*h_filter)[6] = 0.;	(*h_filter)[7] = -0.25;	(*h_filter)[8] = 0.;

	/// Aumentar nitidez 2
	//(*h_filter)[0] = -0.25;	(*h_filter)[1] = -0.25;	(*h_filter)[2] = -0.25;
	//(*h_filter)[3] = -0.25;	(*h_filter)[4] = 3.;	(*h_filter)[5] = -0.25;
	//(*h_filter)[6] = -0.25;	(*h_filter)[7] = -0.25;	(*h_filter)[8] = -0.25;

	//////// FILTROS DE GRADIENTE
	/// Gradiente este
	//(*h_filter)[0] = 1.;	(*h_filter)[1] = 0.;	(*h_filter)[2] = 1.;
	//(*h_filter)[3] = 2.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = -2.;
	//(*h_filter)[6] = 1.;	(*h_filter)[7] = 0.;	(*h_filter)[8] = -1.;

	/// Gradiente norte
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = -2.;	(*h_filter)[2] = -1.;
	//(*h_filter)[3] = 0.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = 0.;
	//(*h_filter)[6] = 1.;	(*h_filter)[7] = 2.;	(*h_filter)[8] = 1.;

	/// Gradiente nordeste
	//(*h_filter)[0] = 0.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = -2.;
	//(*h_filter)[3] = 1.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = -1.;
	//(*h_filter)[6] = 2.;	(*h_filter)[7] = 1.;	(*h_filter)[8] = 0.;

	/// Gradiente noroeste
	//(*h_filter)[0] = -2.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = 0.;
	//(*h_filter)[3] = -1.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = 1.;
	//(*h_filter)[6] = 0.;	(*h_filter)[7] = 1.;	(*h_filter)[8] = 2.;

	/// Gradiente sur
	//(*h_filter)[0] = 1.;	(*h_filter)[1] = 2.;	(*h_filter)[2] = 1.;
	//(*h_filter)[3] = 0.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = 0.;
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = -2.;	(*h_filter)[8] = -1.;

	/// Gradiente oeste
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = 0.;	(*h_filter)[2] = 1.;
	//(*h_filter)[3] = -2.;	(*h_filter)[4] = 0.;	(*h_filter)[5] = 2.;
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = 0.;	(*h_filter)[8] = 1.;

	//////// FILTROS DE DETECCION DE LINEA
	/// Deteccion de linea horizontal
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = -1.;
	//(*h_filter)[3] = 2.;	(*h_filter)[4] = 2.;	(*h_filter)[5] = 2.;
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = -1.;	(*h_filter)[8] = -1.;

	/// Deteccion de linea diagonal izquierda
	//(*h_filter)[0] = 2.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = -1.;
	//(*h_filter)[3] = -1.;	(*h_filter)[4] = 2.;	(*h_filter)[5] = -1.;
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = -1.;	(*h_filter)[8] = 2.;

	/// Deteccion de linea diagonal derecha
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = -1.;	(*h_filter)[2] = 2.;
	//(*h_filter)[3] = -1.;	(*h_filter)[4] = 2.;	(*h_filter)[5] = -1.;
	//(*h_filter)[6] = 2.;	(*h_filter)[7] = -1.;	(*h_filter)[8] = -1.;

	/// Deteccion de linea vertical
	//(*h_filter)[0] = -1.;	(*h_filter)[1] = 2.;	(*h_filter)[2] = -1.;
	//(*h_filter)[3] = -1.;	(*h_filter)[4] = 2.;	(*h_filter)[5] = -1.;
	//(*h_filter)[6] = -1.;	(*h_filter)[7] = 2.;	(*h_filter)[8] = -1.;

	//////// FILTROS DE SUAVIZADO
	/// Media Aritmetica Suave - estandar 3x3
	//(*h_filter)[0] = 0.111;	(*h_filter)[1] = 0.111;	(*h_filter)[2] = 0.111;
	//(*h_filter)[3] = 0.111;	(*h_filter)[4] = 0.111;	(*h_filter)[5] = 0.111;
	//(*h_filter)[6] = 0.111;	(*h_filter)[7] = 0.111;	(*h_filter)[8] = 0.111;
	/// Media Aritmetica Suave - generica NxN
	//float value = 1/(float)(KernelWidth*KernelWidth);
	//for (int i = 0; i < KernelWidth; ++i)
	//	for (int j = 0; j < KernelWidth; ++j)
	//		(*h_filter)[i + KernelWidth * j] = value;

	/// Suavizado 3x3
	//(*h_filter)[0] = 1.;	(*h_filter)[1] = 2.;	(*h_filter)[2] = 1.;
	//(*h_filter)[3] = 2.;	(*h_filter)[4] = 4.;	(*h_filter)[5] = 2.;
	//(*h_filter)[6] = 1.;	(*h_filter)[7] = 2.;	(*h_filter)[8] = 1.;

	/// Suavizado 5x5
	//(*h_filter)[0] = 1.;	(*h_filter)[1] = 1.;    (*h_filter)[2] = 1.;	(*h_filter)[3] = 1.;    (*h_filter)[4] = 1.;
	//(*h_filter)[5] = 1.;	(*h_filter)[6] = 4.;	(*h_filter)[7] = 4.;	(*h_filter)[8] = 4.;	(*h_filter)[9] = 1.;
	//(*h_filter)[10] = 1.;	(*h_filter)[11] = 4.;	(*h_filter)[12] = 12.;	(*h_filter)[13] = 4.;	(*h_filter)[14] = 1.;
	//(*h_filter)[15] = 1.;	(*h_filter)[16] = 4.;	(*h_filter)[17] = 4.;	(*h_filter)[18] = 4.;	(*h_filter)[19] = 1.;
	//(*h_filter)[20] = 1.;	(*h_filter)[21] = 1.;   (*h_filter)[22] = 1.;	(*h_filter)[23] = 1.;   (*h_filter)[24] = 1.;

	//////// FILTROS DE SUAVIZADO
	/// Media Aritmetica Suave
	//(*h_filter)[0] = 0.111;	(*h_filter)[1] = 0.111;	(*h_filter)[2] = 0.111;
	//(*h_filter)[3] = 0.111;	(*h_filter)[4] = 0.111;	(*h_filter)[5] = 0.111;
	//(*h_filter)[6] = 0.111;	(*h_filter)[7] = 0.111;	(*h_filter)[8] = 0.111;
 

}


void convolution(const uchar4 * const h_inputImageRGBA, uchar4 * const d_inputImageRGBA,
	uchar4* const d_outputImageRGBA, const size_t numRows, const size_t numCols,
	unsigned char *d_redFiltered,
	unsigned char *d_greenFiltered,
	unsigned char *d_blueFiltered,
	const int filterWidth)
{
	/// Calcular tama�os de bloque
	//	La tarjeta tiene un maximo de 1024 threads por bloque, por tanto el tamanyo de bloque es de 32
	const dim3 gridSize((numCols-1) / BLOCK_SIZE+1, (numRows-1) / BLOCK_SIZE+1, 1);
	const dim3 blockSize(BLOCK_SIZE, BLOCK_SIZE, 1);

	/// Lanzar kernel para separar imagenes RGBA en diferentes colores
	separateChannels << <gridSize, blockSize >> >(d_inputImageRGBA, numRows, numCols, d_red, d_green, d_blue);

	//Ejecutar convoluci�n. Una por canal
	box_filter << <gridSize, blockSize >> >(d_red, d_redFiltered, numRows, numCols, d_filter, filterWidth);
	box_filter << <gridSize, blockSize >> >(d_green, d_greenFiltered, numRows, numCols, d_filter, filterWidth);
	box_filter << <gridSize, blockSize >> >(d_blue, d_blueFiltered, numRows, numCols, d_filter, filterWidth);

	// Recombining the results. 
	recombineChannels << <gridSize, blockSize >> >(d_redFiltered,
		d_greenFiltered,
		d_blueFiltered,
		d_outputImageRGBA,
		numRows,
		numCols);
	cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

}


//Free all the memory that we allocated
//make sure you free any arrays that you allocated
void cleanup() {
	checkCudaErrors(cudaFree(d_red));
	checkCudaErrors(cudaFree(d_green));
	checkCudaErrors(cudaFree(d_blue));
	checkCudaErrors(cudaFree(d_filter));
}
