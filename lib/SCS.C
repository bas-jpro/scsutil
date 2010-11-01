// C++ Object for accessing SCS files
//
// v1.0 JPRO JCR JR83 31/10/2002 Initial Release
//

#include <SCS.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>

SCS::SCS(void) {
  path = (char *) malloc((strlen(SCSPATH) + 1) * sizeof(char));
  strncpy(path, SCSPATH, strlen(SCSPATH));

  delim = SCSDELIM;

  name = (char *) NULL;
  stream = (FILE *) NULL;
  
  record = (Record *) NULL;

  vars = (char **) NULL;
  n_vars = 0;
}

SCS::~SCS(void) {
  if (path != (char *) NULL) {
	free(path);
  }
  
  if (name != (char *) NULL) {
	free(name);
  }

  if (stream != (FILE *) NULL) {
	fclose(stream);
  }

  if (record != (Record *) NULL) {
	free_record(record);
  }

  if (vars != (char **) NULL) {
	free_vars();
  }
}

void SCS::free_vars(void) {
  if (vars == (char **) NULL) {
	return;
  }

  for (int i=0; i<n_vars; i++) {
	if (vars[i] != (char *) NULL) {
	  free(vars[i]);
	}
  }

  free(vars);

  vars = (char **) NULL;
  n_vars = 0;
}

void SCS::free_record(Record *rec) {
  if (rec == (Record *) NULL) {
	return;
  }

  if (rec->vals != (double *) NULL) {
	free(rec->vals);
  }

  free(rec);
}

Record *SCS::new_record(int n) {
  Record *rec = (Record *) malloc(sizeof(Record));

  rec->vals = (double *) malloc(sizeof(double) * n);
  rec->n_vals = n;

  return rec;
}

char **SCS::split(char *str) {
  char *token;
  static char *list[MAXELEMENTS];
  int i = 0;
  char DELIM[2];

  DELIM[0] = delim;
  DELIM[1] = '\0';

  token = strtok(str, DELIM);
  
  list[i++] = token;
  while   ( ((token=strtok(NULL, DELIM)) != NULL) &&
            (i<MAXELEMENTS)) { /*buffer overflow is bad.*/
    list[i++] = token;
  }

  return(list);
}

void SCS::convert(char *buf) {
  // Split input line into year, day_fract, (jday), (jday_fract), vars ...
  char **fs = split(buf);

  record->year = atoi(fs[0]);
  record->day_fract = atof(fs[1]);

  for (int i=0; i<n_vars; i++) {
	record->vals[i] = atof(fs[4+i]);
  }
}

int SCS::attach(char *str) {
  name = (char *) malloc((strlen(str) + 1) * sizeof(char));
  strncpy(name, str, strlen(str));

  char *stream_name = (char *) malloc((strlen(path) + strlen(str) + strlen(SCSDATAEXT) + 2) * sizeof(char));
  strncpy(stream_name, path, strlen(path));
  strncat(stream_name, "/", 2);
  strncat(stream_name, str, strlen(str));
  strncat(stream_name, SCSDATAEXT, strlen(SCSDATAEXT));

  stream = fopen(stream_name, "r");

  free(stream_name);

  if (!stream) {
	return -1;
  }

  // Seems to be a possible compiler/library bug (gcc v3.1 Solaris 2.8) - use calloc instead of malloc
  char *tpl_name = (char *) calloc((strlen(SCSPATH) + strlen(name) + strlen(SCSTPLEXT) + 2), sizeof(char));
  tpl_name[0] = '\0';
  strncpy(tpl_name, SCSPATH, strlen(SCSPATH));
  strncat(tpl_name, "/", 2);
  strncat(tpl_name, name, strlen(name));
  strncat(tpl_name, SCSTPLEXT, strlen(SCSTPLEXT));

  FILE *tp = fopen(tpl_name, "r");

  free(tpl_name);

  if (!tp) {
	return -2;
  }

  if (vars != (char **) NULL) {
	free_vars();
  }
  vars = (char **) NULL;
  n_vars = 0;

  char buf[SCSBUF];
  fgets(buf, SCSBUF, tp);
  
  while (!feof(tp)) {
	n_vars++;
	vars = (char **) realloc((void *) vars, sizeof(char **) * n_vars);

	char **fs = split(buf);
	
	vars[n_vars - 1] = (char *) malloc((strlen(fs[1]) + 1) * sizeof(char));
	strncpy(vars[n_vars - 1], fs[1], strlen(fs[1]));

	fgets(buf, SCSBUF, tp);
  }

  record = new_record(n_vars);

  return 0;
}

int SCS::detach(void) {
  if (stream == (FILE *) NULL) {
	return -1;
  }

  fclose(stream);

  free_record(record);

  record = (Record *) NULL;

  stream = (FILE *) NULL;

  if (name == (char *) NULL) {
	free(name);
  }

  return 0;
}

int SCS::get_var(char *varname) {
  if (n_vars == 0) {
	return -1;
  }

  for (int i=0; i<n_vars; i++) {
	if (strncmp(varname, vars[i], strlen(vars[i])) == 0) {
	  return i;
	}
  }

  return -2;
}

Record *SCS::next_record(void) {
  if (stream == (FILE *) NULL) {
	return (Record *) NULL;
  }

  char buf[SCSBUF];

  char *ptr = fgets(buf, SCSBUF, stream);

  if (feof(stream) || (ptr == (char *) NULL)) {
	return (Record *) NULL;
  }

  convert(buf);

  return record;
}

Record *SCS::last_record(void) {
  if (stream == (FILE *) NULL) {
	return (Record *) NULL;
  }

  char buf[SCSBUF];

  // Seek to end less a bit
  fseek(stream, -4096, SEEK_END);

  // Get fragment of line
  char *ptr = fgets(buf, SCSBUF, stream);
  
  // Now find last record
  ptr = fgets(buf, SCSBUF, stream);
  while (ptr != (char *) NULL) {
	convert(buf);
	
	ptr = fgets(buf, SCSBUF, stream);
  }
  
  return record;
}

void SCS::rvs_to_scs_time(char *time_str, int *year, double *day_fract) {
  if ((strlen(time_str) != 9) && (strlen(time_str) != 11)) {
	fprintf(stderr, "bad time\n");
	exit(-1);
  }

  char year_str[3];
  strncpy(year_str, time_str, 2);
  year_str[2] = '\0';

  *year = atoi(year_str);
  
  // Y2K compliance
  if (*year < 69) {
	*year += 2000;
  } else {
	*year += 1900;
  }

  char jday_str[4];
  strncpy(jday_str, &time_str[2], 3);
  jday_str[3] = '\0';

  int jday = atoi(jday_str);

  char hour_str[3];
  strncpy(hour_str, &time_str[5], 2);
  hour_str[2] = '\0';
  
  int hour = atoi(hour_str);

  char min_str[3];
  strncpy(min_str, &time_str[7], 2);
  min_str[2] = '\0';

  int min = atoi(min_str);

  int sec = 0;
  if (strlen(time_str) == 11) {
	char sec_str[3];
	strncpy(sec_str, &time_str[9], 2);
	sec_str[2] = '\0';

	sec = atoi(sec_str);
  }

  *day_fract = double(jday) + ((double(sec) + 60.0 * (double(min) + 60.0 * double(hour))) / double(SECSPERDAY));
}

// Use a binary search to find a given start time and set filepos
// Based on version from book "Mastering Algorithms with Perl"
Record *SCS::find_time(int year, double day_fract) {
  long low = 0, mid = 0, mid2 = 0, high = 0;

  // Get file size
  char *stream_name = (char *) malloc((strlen(path) + strlen(name) + strlen(SCSDATAEXT) + 2) * sizeof(char));
  strncpy(stream_name, path, strlen(path));
  strncat(stream_name, "/", 2);
  strncat(stream_name, name, strlen(name));
  strncat(stream_name, SCSDATAEXT, strlen(SCSDATAEXT));

  struct stat file_stat;
  stat(stream_name, &file_stat);

  high = file_stat.st_size;

  char buf[SCSBUF];
  char *ptr = (char *) NULL;

  while (high != low) {
	mid = int((high + low) / 2);

	fseek(stream, mid, SEEK_SET);

	// read rest of line in case in middle
	ptr = fgets(buf, SCSBUF, stream);
	mid2 = ftell(stream);

	if (mid2 < high) {
	  // Not near end of file
	  mid = mid2;
	  ptr = fgets(buf, SCSBUF, stream);
	} else {
	  // At last line so linear search
	  fseek(stream, low, SEEK_SET);
	  
	  ptr = fgets(buf, SCSBUF, stream);
	  while (ptr != (char *) NULL) {
		char **fs = split(buf);

		if (compare_scs_time(atoi(fs[0]), atof(fs[1]), year, day_fract) >= 0) {
		  break;
		}

		low = ftell(stream);

		ptr = fgets(buf, SCSBUF, stream);
	  }
	  
	  break;
	}

	char **fs = split(buf);
	if (compare_scs_time(atoi(fs[0]), atof(fs[1]), year, day_fract) < 0) {
	  low = mid;
	} else {
	  high = mid;
	}
  }

  // If we fell off the end of the file return last record
  if (ptr) {
	convert(buf);
  } else {
	last_record();
  }

  return record;
}

int SCS::compare_scs_time(int y1, double d1, int y2, double d2) {
  if (y1 == y2) {
	if (d1 < d2) {
	  return -1;
	}

	if (d1 > d2) {
	  return 1;
	}

	return 0;
  }

  if (y1 < y2) {
	return -1;
  }

  if (y1 > y2) {
	return 1;
  }

  // This is impossible, anyway ....
  return 0;
}

