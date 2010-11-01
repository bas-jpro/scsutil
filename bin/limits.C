// SCS Version of RVS limits utility
// 
// v1.0 JPRO JCR JR83 31/10/2002 Initial Release
//                               Written in C/C++ for speed over perl version
//
// limits [-s stime] [-e etime] [-v] [-l stat] stream var1 [var2...]
//
// Note: -l recognised but ignored.
//
// 

#include <SCS.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

char *start_time = (char *) NULL, *end_time = (char *) NULL, *stream = (char *) NULL;
int *vars = (int *) NULL, n_vars = 0;
int verbose = 0;

void usage(char *);

int main(int argc, char *argv[]) {
 extern char *optarg;
 extern int optind, opterr, optopt;

 int c;

 while ((c = getopt(argc, argv, "s:e:vl:")) != EOF) {
   switch(c) {
   case 's': 
	 start_time = (char *) malloc((strlen(optarg) + 1) * sizeof(char));
	 strncpy(start_time, optarg, strlen(optarg));
	 break;
   case 'e':
	 end_time = (char *) malloc((strlen(optarg) + 1) * sizeof(char));
	 strncpy(end_time, optarg, strlen(optarg));
	 break;
   case 'v':
	 verbose = 1;
	 break;
   case 'l':
	 // All data is GOOD so do nothing
	 break;
   default:
	 usage("limits");
	 break;
   }
 }

 // Must have stream name and at least 1 var
 if ((argc - optind) < 2) {
   usage("limits");
 }

 // Initialize an SCS object
 SCS scs;

 int stream = optind;

 if (scs.attach(argv[stream]) < 0) {
   fprintf(stderr, "limits: Failed to attach %s - no stream\n", argv[stream]);
   exit(-2);
 }
 optind++;
 
 n_vars = argc - optind;
 vars = (int *) malloc(sizeof(int) * n_vars);
 
 for (int i=0; i<n_vars; i++) {
   vars[i] = scs.get_var(argv[optind+i]);

   if (vars[i] < 0) {
	 fprintf(stderr, "limits: Failed to attach %s - mismatch\n", argv[stream]);
	 exit(-3);
   }
 }

 double *mins = (double *) malloc(sizeof(int) * n_vars);
 double *maxs = (double *) malloc(sizeof(int) * n_vars);

 Record *rec = scs.next_record();

 if (start_time != (char *) NULL) {
   int year = 0;
   double day_fract;
   scs.rvs_to_scs_time(start_time, &year, &day_fract);

   rec = scs.find_time(year, day_fract);
 }

 for (int i=0; i<n_vars; i++) {
   mins[i] = rec->vals[vars[i]];
   maxs[i] = rec->vals[vars[i]];
 }

 int end_year = 2100;
 double end_day_fract = 400.0;
 if (end_time != (char *) NULL) {
   scs.rvs_to_scs_time(end_time, &end_year, &end_day_fract);
 }

 while ((rec != (Record *) NULL) && (scs.compare_scs_time(rec->year, rec->day_fract, end_year, end_day_fract) <= 0)) {
   for (int i=0; i<n_vars; i++) {
	 if (rec->vals[vars[i]] < mins[i]) {
	   mins[i] = rec->vals[vars[i]];
	 }

	 if (rec->vals[vars[i]] > maxs[i]) {
	   maxs[i] = rec->vals[vars[i]];
	 }
   }

   rec = scs.next_record();
 }

 for (int i=0; i<n_vars; i++) {
   fprintf(stdout, "%lf %lf\n", maxs[i], mins[i]);
 }

 if (start_time != (char *) NULL) {
   free(start_time);
 }
 
 if (end_time != (char *) NULL) {
   free(end_time);
 }

 if (vars != (int *) NULL) {
   free(vars);
 }

 if (mins != (double *) NULL) {
   free(mins);
 }

 if (maxs != (double *) NULL) {
   free(maxs);
 }

 return 0;
}

void usage(char *progname) {
  fprintf(stderr, "%s [-s stime] [-e etime] [-v] [-l stat] stream var [var...]\n", progname);
  exit(-1);
}
