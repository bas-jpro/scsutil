// C++ Object for accessing SCS files -*-C++-*-
//
// v1.0 JPRO JCR JR83 31/10/2002 Initial Release
//

#ifndef SCSH
#define SCSH

#include <sys/types.h>
#include <stdio.h>

#define SCSPATH    "/scs"
#define SCSDELIM   ','
#define SCSBUF     4096
#define SCSDATAEXT ".ACO"
#define SCSTPLEXT  ".TPL"

#define SECSPERDAY  60 * 60 * 24
#define MAXELEMENTS 1024

struct Record {
  int year;
  double day_fract;
  double *vals;
  int n_vals;
};

class SCS {
  char *path;
  char delim;
  
  char *name;
  FILE *stream;
  Record *record;
	
  char **vars;
  int n_vars;

  void free_vars(void);
  void free_record(Record *);
  Record *new_record(int);
  /* noop@nwonknu.org was here */
  char **split(char *);
  void convert(char *);
  
public:
  SCS(void);
  ~SCS(void);

  int attach(char *);
  int detach(void);
  int get_var(char *);
  Record *next_record(void);
  Record *last_record(void);
  void rvs_to_scs_time(char *, int *, double *);
  Record *find_time(int, double);
  int compare_scs_time(int, double, int, double);
};

#endif
