
#include <iostream>
#include <fstream>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "okFrontPanel.h"

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#define Sleep(ms)    usleep(ms*1000)
#endif

// Check for a 64-bit environment
#if defined(__amd64__) || defined(_M_X64) || defined(__LP64__) || defined(_LP64)
#define ARCH_X64
#endif

// Check for Microsoft compiler for printf compatibility
#ifdef _MSC_VER
#define LL_FMT_SPEC "I64"
#else
#define LL_FMT_SPEC "ll"
#endif

#define XILINX_CONFIGURATION_FILE  "daq_top.bit"
#define ALTERA_CONFIGURATION_FILE  "daq_top.rbf"
#define CAPABILITY_CALIBRATION     0x01
#define STATUS_CALIBRATION         0x01
#define BLOCK_SIZE                 512             
#define READBUF_SIZE               (8*1024*1024)	
#define WRITE_SIZE                 (8LL*1024LL*1024LL)
#define READ_SIZE                  (8LL*1024LL*1024LL)    
#define NUM_TESTS                  10
#define MIN(x,y)                   ( (x<y) ? (x) : (y) )

unsigned char* g_buf, * g_rbuf;
long long g_nMems, g_nMemSize;
okTDeviceInfo* g_devInfo;


// From mt_random.cpp
void mt_init();
unsigned long mt_random();


//Če pride do problemov z komunikacijo med FPGA in programom se izvede naslednja funkcija
bool
exitOnError(okCFrontPanel::ErrorCode error)
{
	switch (error) {
	case okCFrontPanel::DeviceNotOpen:
		printf("Device no longer available.\n");
		exit(EXIT_FAILURE);
	case okCFrontPanel::Failed:
		printf("Transfer failed.\n");
		exit(EXIT_FAILURE);
	case okCFrontPanel::Timeout:
		printf("   ERROR: Timeout\n");
		return false;
	case okCFrontPanel::TransferError:
		std::cout << "   ERROR: TransferError" << '\n';
		return false;
	case okCFrontPanel::UnsupportedFeature:
		printf("   ERROR: UnsupportedFeature\n");
		return false;
	case okCFrontPanel::DoneNotHigh:
	case okCFrontPanel::CommunicationError:
	case okCFrontPanel::InvalidBitstream:
	case okCFrontPanel::FileError:
	case okCFrontPanel::InvalidEndpoint:
	case okCFrontPanel::InvalidBlockSize:
	case okCFrontPanel::I2CRestrictedAddress:
	case okCFrontPanel::I2CBitError:
	case okCFrontPanel::I2CUnknownStatus:
	case okCFrontPanel::I2CNack:
	case okCFrontPanel::FIFOUnderflow:
	case okCFrontPanel::FIFOOverflow:
	case okCFrontPanel::DataAlignmentError:
	case okCFrontPanel::InvalidParameter:
		std::cout << "   ERROR: " << error << '\n';
		return false;
	default:
		return true;
	}
}


void
readSDRAM(okCFrontPanel& dev, int mem, int n)
{
	okTDeviceInfo* info = new okTDeviceInfo;
	long long i, j, k, read;
	long ret;
	int data_out;
	unsigned int time_stamp;
	unsigned int t0;
	float data; 


	// Reset FIFO
	dev.SetWireInValue(0x00, 0x0004);
	dev.UpdateWireIns();
	dev.SetWireInValue(0x00, 0x0000);
	dev.UpdateWireIns();

	// Nastavi sigal za omogočanje branja iz SRAM pomnilnika
	dev.SetWireInValue(0x00, 0x0001);
	dev.UpdateWireIns();
	printf("   Reading from memory(%d)...\n", mem);

	// generiramo izhodno .csv datoteko
	std::ofstream outfile;

	outfile.open("izhod_" + std::to_string(n) + ".csv");
	outfile << "timestamp;data\n";

	//Zajem podatkov preko PipeOut končne točke
	for (i = 0; i < 8388608; ) {		
		read = MIN(READ_SIZE, 8388608 - i);	
		if (OK_INTERFACE_USB3 == g_devInfo->deviceInterface) {
			ret = dev.ReadFromBlockPipeOut(0xA0 + mem, BLOCK_SIZE, (long)read, g_rbuf);

			//podatki se shranjujejo v tabelo na posamezenem naslovu tabele se nahaja 1 bajt poddatkov za 32 bitni zapis skupaj zružimo 4 elemente tabele
			for (long long m = 0; m < 104000; m = m + 8) {
				if (m == 0) {
					t0 = ((g_rbuf[m + 3] << 24) | ((g_rbuf[m + 2] & 0xFF) << 16) | ((g_rbuf[m + 1] & 0xFF) << 8) | (g_rbuf[m] & 0xFF));
				}
				//iz prebranih podatkov ločimo podatek o časovnem žigu in napetosti
				time_stamp = (((g_rbuf[m + 3] << 24) | ((g_rbuf[m + 2] & 0xFF) << 16) | ((g_rbuf[m + 1] & 0xFF) << 8) | (g_rbuf[m] & 0xFF))- t0)*10;
				data_out = (g_rbuf[m + 7] << 24) | ((g_rbuf[m + 6] & 0xFF) << 16) | ((g_rbuf[m + 5] & 0xFF) << 8) | (g_rbuf[m + 4] & 0xFF);
				data = (data_out*1.0)/ 4096; 
				outfile << time_stamp << ";" << data << "\n";
			}
		}
		else {
			ret = okCFrontPanel::UnsupportedFeature;
		}

		if (false == exitOnError((okCFrontPanel::ErrorCode)ret)) {
			break;
		}
		i += read;
	}

	if (false == dev.IsOpen()) {
		exitOnError(okCFrontPanel::DeviceNotOpen);
	}

	outfile.close();

	// Reset FIFO
	dev.SetWireInValue(0x00, 0x0004);
	dev.UpdateWireIns();
	dev.SetWireInValue(0x00, 0x0000);
	dev.UpdateWireIns();

}


OpalKelly::FrontPanelPtr
initializeFPGA()
{
	// Povezava integracijskega modula
	OpalKelly::FrontPanelPtr dev = OpalKelly::FrontPanelDevices().Open();
	if (!dev.get()) {
		printf("Naprava se ne mora povezati.  Je povezana?\n");
		return(dev);
	}


	printf("Povezana naprava: %s\n", dev->GetBoardModelString(dev->GetBoardModel()).c_str());
	g_devInfo = new okTDeviceInfo;
	dev->GetDeviceInfo(g_devInfo);

	//če ni povezan integracijski modul XEM7310-A200 prekini program
	if (dev->GetBoardModel() != okCFrontPanel::brdXEM7310A200) {
		printf("Nepodprta naprava.\n");
		dev.reset();
		return(dev);
	}


	// natsavti parametre pomnilnika 
	g_nMemSize = 2 * 512 * 1024 * 1024;
	g_nMems = 1;

	// Konfiguracija PLL
	dev->LoadDefaultPLLConfiguration();

	// Na FPGA prenesi konfiguracijsko datoteko - bitfile
	std::string config_filename;
	config_filename = XILINX_CONFIGURATION_FILE;

	//Preverimo ali je konfiguracija uspešna
	if (okCFrontPanel::NoError != dev->ConfigureFPGA(config_filename)) {
		printf("FPGA konfiguracija je neuspešna.\n");
		dev.reset();
		return(dev);
	}

	Sleep(2000);

	// Preverimo ali je na na FPGA omogočen FrontPanel
	if (false == dev->IsFrontPanelEnabled()) {
		printf("FrontPanel ni omogočen.\n");
		dev.reset();
		return(dev);
	}

	printf("FrontPanel je omogočen.\n");

	//Kalbiracija pomnilnika
	printf("Kalibracija pomnilnika...\n");
	Sleep(2000); // Čakamo da se konča kalbiracija pomnilnika

	dev->UpdateWireOuts();
	if ((dev->GetWireOutValue(0x3E) & CAPABILITY_CALIBRATION) == CAPABILITY_CALIBRATION) {
		//printf("Preverjanje stanje kali...\n");
		if ((dev->GetWireOutValue(0x20) & STATUS_CALIBRATION) != STATUS_CALIBRATION) {
			printf("Kalibracija neuspešna \n");
			exit(EXIT_FAILURE);
		}
		printf("Kalibracija uspešna \n");
	}

	return(dev);
}


static void
printUsage(char* progname)
{
	printf("Usage: %s\n", progname);
}


int
real_main(int argc, char* argv[])
{
	printf("---- Sistem za zajem podatkov ----\n");
	


	if (argc > 1) {
		printUsage(argv[0]);
		return(-1);
	}

	// Inicializacija FPGA
	OpalKelly::FrontPanelPtr dev = initializeFPGA();
	if (!dev.get()) {
		printf("FPGA ne mora biti inicializiran.\n");
		return(-1);
	}


	// Alociraj spomin za kasnejše branje podatkov iz FPGA
	g_buf = new unsigned char[g_nMemSize];
	g_rbuf = new unsigned char[READBUF_SIZE];

	int data_in;
	int wire_end = 0;
	int scanf_return;

	//reset FIFO na FPGA
	dev->SetWireInValue(0x08, 0x0000);
	dev->UpdateWireIns();

	//zajemi podatkov
	for (int i = 0; ; i++){

		printf("Za enkratni zajem pritisni 1, za konec zajema pritisni 0:");
		scanf_return = scanf("%d", &data_in);
		if (data_in != 1) {
			break;
		}

		if (scanf_return == 0) {
			printf("Failed to read an integer.\n");
		}

		data_in = 0;
		scanf_return = 0;

		float trig_float; 
		unsigned int trig;

		//Nasavitev prožilca
		printf("Vnesi vrednost triggerja (vrednost med 0 in 1):");
		scanf_return = scanf("%f", &trig_float);

		if (scanf_return == 0) {
			printf("Failed to read an integer.\n");
		}
		trig = (int)(trig_float * 4096);
		dev->SetWireInValue(0x10, trig);
		dev->UpdateWireIns();


		//začetek vpisovanja podatkov v SRAM
		dev->SetWireInValue(0x08, 0x0001);
		dev->UpdateWireIns();
		
		//Čakaj da se vpisovanje konča
		dev->UpdateWireOuts();
		wire_end = dev->GetWireOutValue(0x34);
		while (!wire_end) {
			dev->UpdateWireOuts();
			wire_end = dev->GetWireOutValue(0x34);
		}

		wire_end = 0; 

		//Ponastavi signal za omogočanje vpisovanja podatkov v SRAM
		dev->SetWireInValue(0x08, 0x0000);
		dev->UpdateWireIns();

		Sleep(2000);

		//Preberi podatke iz SRAM 
		int  j;
		for (j = 0; j < g_nMems; j++) {
			readSDRAM(*dev, j, i);
		}

		//konec pisanja
		dev->SetWireInValue(0x08, 0x0000);
		dev->UpdateWireIns();
	
	}


	// Free allocated storage.
	delete[] g_buf;
	delete[] g_rbuf;

	return(0);
}


int
main(int argc, char* argv[])
{
	try {
		return real_main(argc, argv);
	}
	catch (std::exception const& e) {
		fprintf(stderr, "Error: %s\n", e.what());
	}
	catch (...) {
		fprintf(stderr, "Error: caught unknown exception.\n");
	}

	return -1;
}
