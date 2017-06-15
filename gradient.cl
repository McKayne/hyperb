#pragma OPENCL EXTENSION cl_khr_fp64 : enable

#define NUMBER_OF_DAMPERS 1
#define N 160
#define K 64

typedef struct alphastruct {
	double a, b, c, d;
} cl_matrix2x2;

typedef struct betastruct {
	double a, b;
} cl_matrix2x1;

__kernel void gradientAt(double energyInt, __global double* grad, __global double* wt, __global double* damperX, __global double* pu, double a, double l, double t, __global int* noFault) {

	double derH = 0.0001;
	double hx = l / N;
	double ht = t / K;

	double alpha = 2.0 * pow(hx, 2) / (a * ht);
	double beta = pow(hx, 2) / a;

	cl_matrix2x2 e2;
	e2.a = 2.0;
	e2.b = 0.0;
	e2.c = 0.0;
	e2.d = 2.0;

	cl_matrix2x2 bAlpha;
	bAlpha.a = 0.0;
	bAlpha.b = -alpha;
	bAlpha.c = alpha;
	bAlpha.d = 0.0;

	cl_matrix2x2 c;
	c.a = e2.a + bAlpha.a;
	c.b = e2.b + bAlpha.b;
	c.c = e2.c + bAlpha.c;
	c.d = e2.d + bAlpha.d;

	cl_matrix2x2 cInverted;
	double detDenominator = c.a * c.d - c.b * c.c;
	cInverted.a = c.d / detDenominator;
	cInverted.b = -c.b / detDenominator;
	cInverted.c = -c.c / detDenominator;
	cInverted.d = c.a / detDenominator;

	cl_matrix2x2 cTilde;
	cTilde.a = e2.a - bAlpha.a;
	cTilde.b = e2.b - bAlpha.b;
	cTilde.c = e2.c - bAlpha.c;
	cTilde.d = e2.d - bAlpha.d;

	cl_matrix2x2 sweepAlphaArr[N - 2];
	cl_matrix2x2 temp, invTemp;

	cl_matrix2x1 sweepBetaArr[N - 1];
	cl_matrix2x1 y0, y1, y2;
	cl_matrix2x1 temp1, temp2, temp3;
	cl_matrix2x1 currentV;

	double fA, fB, x, wA, wB, fNew, numInt, dx;

	sweepAlphaArr[0].a = cInverted.a;
	sweepAlphaArr[0].b = cInverted.b;
	sweepAlphaArr[0].c = cInverted.c;
	sweepAlphaArr[0].d = cInverted.d;
	for (int i = 1; i < N - 2; i++) {
		temp.a = c.a - sweepAlphaArr[i - 1].a;
		temp.b = c.b - sweepAlphaArr[i - 1].b;
		temp.c = c.c - sweepAlphaArr[i - 1].c;
		temp.d = c.d - sweepAlphaArr[i - 1].d;

		detDenominator = temp.a * temp.d - temp.b * temp.c;
		sweepAlphaArr[i].a = temp.d / detDenominator;
		sweepAlphaArr[i].b = -temp.b / detDenominator;
		sweepAlphaArr[i].c = -temp.c / detDenominator;
		sweepAlphaArr[i].d = temp.a / detDenominator;
	}

	double u[N + 1];
	double v[N + 1];
	double f[N + 1];
	double bu[N + 1];
	double bwt[K + 1];

	for (int i = 0; i < N + 1; i++) {
		bu[i] = pu[i];
	}
	for (int i = 0; i < K + 1; i++) {
		bwt[i] = wt[i];
	}
	for (int i = 0; i < N + 1; i++) {
		u[i] = bu[i];
		v[i] = 0.0;
	}

	for (int nth = 0; nth <= K; nth++) {
		bwt[nth] += derH;
		for (int i = 1; i <= K; i++) {
			for (int j = 1; j < N; j++) {
				if (i == 1) {
					y0.a = bu[j - 1];
					y0.b = 0.0;

					y1.a = bu[j];
					y1.b = 0.0;

					y2.a = bu[j + 1];
					y2.b = 0.0;
				} else {
					y0.a = u[j - 1];
					y0.b = v[j - 1];

					y1.a = u[j];
					y1.b = v[j];

					y2.a = u[j + 1];
					y2.b = v[j + 1];
				}
				
				temp1.a = cTilde.a * y1.a + cTilde.b * y1.b;
				temp1.b = cTilde.c * y1.a + cTilde.d * y1.b;

				temp2.a = y0.a;
				temp2.b = y0.b;

				temp2.a -= temp1.a;
				temp2.b -= temp1.b;

				temp2.a += y2.a;
				temp2.b += y2.b;

				fA = 0.0;
				fB = 0.0;
				x = hx * j;

				wA = bwt[i - 1];
				wB = bwt[i];

				fNew = -x * (1.0 - 0.5);
				if (x >= 0.5) {
					fNew += 1.0 * (x - 0.5);
				}

				fA += fNew * wA;
				fB += fNew * wB;

				currentV.a = -fA - fB;
				currentV.b = 0.0;

				currentV.a *= beta;
				currentV.b *= beta;

				temp2.a += currentV.a;
				temp2.b += currentV.b;

				if (j == 1) {
					sweepBetaArr[0].a = cInverted.a * temp2.a + cInverted.b * temp2.b;
					sweepBetaArr[0].b = cInverted.c * temp2.a + cInverted.d * temp2.b;
				} else {
					temp.a = c.a - sweepAlphaArr[j - 2].a;
					temp.b = c.b - sweepAlphaArr[j - 2].b;
					temp.c = c.c - sweepAlphaArr[j - 2].c;
					temp.d = c.d - sweepAlphaArr[j - 2].d;

					detDenominator = temp.a * temp.d - temp.b * temp.c;
					invTemp.a = temp.d / detDenominator;
					invTemp.b = -temp.b / detDenominator;
					invTemp.c = -temp.c / detDenominator;
					invTemp.d = temp.a / detDenominator;

					temp3.a = sweepBetaArr[j - 2].a;
					temp3.b = sweepBetaArr[j - 2].b;
					temp3.a += temp2.a;
					temp3.b += temp2.b;

					sweepBetaArr[j - 1].a = invTemp.a * temp3.a + invTemp.b * temp3.b;
					sweepBetaArr[j - 1].b = invTemp.c * temp3.a + invTemp.d * temp3.b;
				}
			}

			u[N - 1] = sweepBetaArr[N - 2].a;
			v[N - 1] = sweepBetaArr[N - 2].b;

			for (int j = N - 2; j > 0; j--) {
				u[j] = sweepAlphaArr[j - 1].a * u[j + 1] + sweepAlphaArr[j - 1].b * v[j + 1] + sweepBetaArr[j - 1].a;
				v[j] = sweepAlphaArr[j - 1].c * u[j + 1] + sweepAlphaArr[j - 1].d * v[j + 1] + sweepBetaArr[j - 1].b;
			}

			if (i == K - 2) {
				for (int j = 0; j <= N; j++) {
					f[j] = u[j];
				}
			}
			if (i == K - 1) {
				for (int j = 0; j <= N; j++) {
					f[j] = f[j] - 4.0 * u[j];
				}
			}
			if (i == K) {
				for (int j = 0; j <= N; j++) {
					f[j] = f[j] + 3.0 * u[j];
					f[j] = f[j] / 2.0;
					f[j] = f[j] / ht;
					f[j] = f[j] * f[j];

					dx = 0.0;
					if (j == 0) {
						dx = (-3.0 * u[j] + 4.0 * u[j + 1] - u[j + 2]) / (2.0 * hx);
					} else if (j == N) {
						dx = (u[N - 2] - 4.0 * u[N - 1] + 3.0 * u[N]) / (2.0 * hx);
					} else {
						dx = (u[j - 1] - 2.0 * u[j] + u[j + 1]) / (hx * hx);
					}
					dx = dx * dx;
					f[j] = f[j] + dx;
				}
			}
		}

		numInt = f[0];
		for (int i = 1; i < N; i += 2) {
			numInt += 4.0 * f[i];
		}
		for (int i = 2; i < N; i += 2) {
			numInt += 2.0 * f[i];
		}
		numInt += f[N];
		numInt *= hx / 3.0;

		grad[nth] = (numInt - energyInt) / derH;
		bwt[nth] -= derH;
	}




	noFault[0] = 1;
}
