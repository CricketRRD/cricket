/*
 * getFormat
 *
 * Program that computes the rrd_format structures for Cricket Arch.
 *
 * To compile:
 *		gcc -I<path to RRD Tool's src dir> -o getFormat getFormat.c
 *
 * I make an assumptions that the unival unions arrays are linear and there 
 * is NO padding other than the normal padding for unions and that the double
 * value of the union is bigger than the unsigned long...
 *
 * Contributed by Ed Bugg <Bugge@ABCBS.com>. Bug fixes by Melissa
 * D. Binde <binde@amazon.com> and Jeff Allen <jra@corp.webtv.net>.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <ctype.h>

#include <rrd_format.h>

void format_stat_head (void) {
  stat_head_t h1;
  size_t addr1, addr2;
  int pad;  /* Padding if needed */
  int total=0;
  char rrdFormat[80];

  memset(rrdFormat, 0, sizeof(rrdFormat));

  addr1 = (size_t)&h1.cookie;
  addr2 = (size_t)&h1.version;
  if ((addr2 - addr1) == sizeof(h1.cookie)) {
    sprintf(rrdFormat, "a4");
  } else {
    pad = addr2 - addr1 - sizeof(h1.cookie);
    sprintf(rrdFormat, "a4 x%d", pad);
    total += pad;
  }
  total += sizeof(h1.cookie);

  addr1 = addr2;
  addr2 = (size_t)&h1.float_cookie;
  if ((addr2 - addr1) == sizeof(h1.version)) {
    sprintf(rrdFormat, "%s a5", rrdFormat);
  } else {
    pad = addr2 - addr1 - sizeof(h1.version);
    sprintf(rrdFormat, "%s a5 x%d", rrdFormat, pad);
    total += pad;
  }
  total += sizeof(h1.version);

  addr1 = addr2;
  addr2 = (size_t)&h1.ds_cnt;
  if ((addr2 - addr1) == sizeof(h1.float_cookie)) {
    sprintf(rrdFormat, "%s d", rrdFormat);
  } else {
    pad = addr2 - addr1 - sizeof(h1.float_cookie);
    sprintf(rrdFormat, "%s d x%d", rrdFormat, pad);
    total += pad;
  }
  total += sizeof(h1.float_cookie);

  addr1 = addr2;
  addr2 = (size_t)&h1.rra_cnt;
  if ((addr2 - addr1) == sizeof(h1.ds_cnt)) {
    sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(h1.ds_cnt)==8)?'Q':'L');
  } else {
    pad = addr2 - addr1 - sizeof(h1.ds_cnt);
    sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(h1.ds_cnt)==8)?'Q':'L', pad);
    total += pad;
  }
  total += sizeof(h1.ds_cnt);

  addr1 = addr2;
  addr2 = (size_t)&h1.pdp_step;
  if ((addr2 - addr1) == sizeof(h1.rra_cnt)) {
    sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(h1.rra_cnt)==8)?'Q':'L');
  } else {
    pad = addr2 - addr1 - sizeof(h1.rra_cnt);
    sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(h1.rra_cnt)==8)?'Q':'L', pad);
    total += pad;
  }
  total += sizeof(h1.rra_cnt);

  addr1 = addr2;
  addr2 = (size_t)&h1.par;
  if ((addr2 - addr1) == sizeof(h1.pdp_step)) {
    sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(h1.pdp_step)==8)?'Q':'L');
  } else {
    pad = addr2 - addr1 - sizeof(h1.pdp_step);
    sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(h1.pdp_step)==8)?'Q':'L', pad);
    total += pad;
  }
  total += sizeof(h1.pdp_step);

  pad = sizeof(h1) - total;

  sprintf(rrdFormat, "%s x%d", rrdFormat, pad);
  printf("$self->{'statHead'} = \"%s\"\n", rrdFormat);
}

void format_ds_def (void) {
  ds_def_t h2;
  int total=0;
  char rrdFormat[80];
  size_t addr1, addr2;
  int pad;

  memset(rrdFormat, 0, sizeof(rrdFormat));

  addr1 = (size_t)&h2.ds_nam;
  addr2 = (size_t)&h2.dst;
  if ((addr2 - addr1) == sizeof(h2.ds_nam)) {
    sprintf(rrdFormat, "a%d", DS_NAM_SIZE);
  } else {
    pad = addr2 - addr1 - sizeof(h2.ds_nam);
    sprintf(rrdFormat, "a%d x%d", DS_NAM_SIZE, pad);
    total += pad;
  }
  total += sizeof(h2.ds_nam);

  addr1 = addr2;
  addr2 = (size_t)&h2.par;
  if ((addr2 - addr1) == sizeof(h2.dst)) {
    sprintf(rrdFormat, "%s a%d", rrdFormat, DST_SIZE);
  } else {
    pad = addr2 - addr1 - sizeof(h2.dst);
    sprintf(rrdFormat, "%s a%d x%d", rrdFormat, DST_SIZE, pad);
    total += pad;
  }
  total += sizeof(h2.dst);

  /* Heartbeat is a long vs min and max values are doubles */
  if (sizeof(unival) - sizeof(unsigned long)) {
	  sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(unival)==8)?'Q':'L', 
		  sizeof(unival) - sizeof(unsigned long));
  } else {
	  sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(unival)==8)?'Q':'L');
  }
  total += sizeof(unival);

  sprintf(rrdFormat, "%s d d", rrdFormat);
  total += (2* sizeof(unival));

  pad = sizeof(h2) - total;
  if (pad) {
	  sprintf(rrdFormat, "%s x%d", rrdFormat, pad);
  }

  printf("$self->{'dsDef'} = \"%s\"\n", rrdFormat);
}

void format_rra_def   (void) {
  rra_def_t h2;
  int total=0;
  char rrdFormat[80];
  size_t addr1, addr2;
  int pad;

  memset(rrdFormat, 0, sizeof(rrdFormat));

  addr1 = (size_t)&h2.cf_nam;
  addr2 = (size_t)&h2.row_cnt;
  
  if ((addr2 - addr1) == sizeof(h2.cf_nam)) {
    sprintf(rrdFormat, "a%d", CF_NAM_SIZE);
  } else {
    pad = addr2 - addr1 - sizeof(h2.cf_nam);
    sprintf(rrdFormat, "a%d x%d", CF_NAM_SIZE, pad);
    total += pad;
  }
  total += sizeof(h2.cf_nam);
  
  addr1 = addr2;
  addr2 = (size_t)&h2.pdp_cnt;
  if ((addr2 - addr1) == sizeof(h2.row_cnt)) {
    sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(h2.row_cnt)==8)?'Q':'L');
  } else {
    pad = addr2 - addr1 - sizeof(h2.row_cnt);
    sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(h2.row_cnt)==8)?'Q':'L', pad);
    total += pad;
  }
  total += sizeof(h2.row_cnt);

  addr1 = addr2;
  addr2 = (size_t)&h2.par;
  if ((addr2 - addr1) == sizeof(h2.pdp_cnt)) {
    sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(h2.pdp_cnt)==8)?'Q':'L');
  } else {
    pad = addr2 - addr1 - sizeof(h2.pdp_cnt);
    sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(h2.pdp_cnt)==8)?'Q':'L', pad);
    total += pad;
  }
  total += sizeof(h2.pdp_cnt);

  /* xff_val is a double */
  sprintf(rrdFormat, "%s d", rrdFormat);
  total += sizeof(unival);


  pad = sizeof(h2) - total;
  if (pad) {
	  sprintf(rrdFormat, "%s x%d", rrdFormat, pad);
  }

  printf("$self->{'rraDef'} = \"%s\"\n", rrdFormat);
}

void format_live_head (void) {
  char rrdFormat[80];

  memset(rrdFormat, 0, sizeof(rrdFormat));

  sprintf(rrdFormat, "%c", (sizeof(time_t)==8)?'Q':'L');
  printf("$self->{'liveHead'} = \"%s\"\n", rrdFormat);
}

void format_pdp_prep  (void) {
  pdp_prep_t h2;
  int total=0;
  char rrdFormat[80];
  size_t addr1, addr2;
  int pad;

  memset(rrdFormat, 0, sizeof(rrdFormat));

  addr1 = (size_t)&h2.last_ds;
  addr2 = (size_t)&h2.scratch;

  if((addr2 - addr1) == sizeof(h2.last_ds)) {
    sprintf(rrdFormat, "a%d", LAST_DS_LEN);
  } else {
    pad = addr2 - addr1 - sizeof(h2.last_ds);
    sprintf(rrdFormat, "a%d x%d", LAST_DS_LEN, pad);
    total += pad;
  }
  total += sizeof(h2.last_ds);

  /* unknown sec is a long and pdp_val is a double */
  if (sizeof(unival) - sizeof(unsigned long)) {
	  sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(unival)==8)?'Q':'L', 
		  sizeof(unival) - sizeof(unsigned long));
  } else {
	  sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(unival)==8)?'Q':'L');
  }
  total += sizeof(unival);

  sprintf(rrdFormat, "%s d", rrdFormat);
  total += sizeof(unival);

  pad = sizeof(h2) - total;
  if (pad) {
	  sprintf(rrdFormat, "%s x%d", rrdFormat, pad);
  }

  printf("$self->{'pdpDef'} = \"%s\"\n", rrdFormat);
}

void format_cdp_prep  (void) {
  cdp_prep_t h2;
  int total=0;
  char rrdFormat[80];
  int pad;

  memset(rrdFormat, 0, sizeof(rrdFormat));

  sprintf(rrdFormat, "d"); /* cdp_val is a double */
  total += sizeof(unival);

  if (sizeof(unival) - sizeof(unsigned long)) {
	  sprintf(rrdFormat, "%s %c x%d", rrdFormat, (sizeof(unival)==8)?'Q':'L', 
		  sizeof(unival) - sizeof(unsigned long));
  } else {
	  sprintf(rrdFormat, "%s %c", rrdFormat, (sizeof(unival)==8)?'Q':'L');
  }
  total += sizeof(unival);

  pad = sizeof(h2) - total;
  if (pad) {
	  sprintf(rrdFormat, "%s x%d", rrdFormat, pad);
  }

  printf("$self->{'cdpDef'} = \"%s\"\n", rrdFormat);
}

void format_rra_ptr   (void) {
  char rrdFormat[80];

  memset(rrdFormat, 0, sizeof(rrdFormat));

  sprintf(rrdFormat, "%c", (sizeof(&rrdFormat)==8)?'Q':'L');

  printf("$self->{'rraPtr'} = \"%s\"\n", rrdFormat);
}

void format_element   (void) {
  char rrdFormat[80];

  sprintf(rrdFormat, "d"); /* Assuming all data elements are just doubles *
							  This is pretty safe */
  printf("$self->{'element'} = \"%s\"\n", rrdFormat);
}
 
int main (void) {

  format_stat_head();
  format_ds_def();
  format_rra_def(); 
  format_pdp_prep();
  format_cdp_prep();
  format_live_head();
  format_rra_ptr();
  format_element();

  return 0;
}
