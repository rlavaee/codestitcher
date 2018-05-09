#include "test_util.h"
int main(){
	int a = 1;
	for(long long i = 0; i < ((long long)(100000))*100000; i++){
		if(i%5==0)
			a = f(a);
		else
			a = g(a);
	}
	return a-1;
}
