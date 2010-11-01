# Useful constants for SCS Web Interface
#
# v1.0 JPRO JCR JR83 03/11/2002 Initial Release
#

package Apache::SCS::Constants;
use strict;
use vars qw($SCS_YEARS $SCS_MONTH_NUMS $SCS_MONTH_NAMES $SCS_DAYS $SCS_HOURS $SCS_MINSEC);
 
$SCS_YEARS = [1998..2019];

$SCS_MONTH_NUMS  = ['01', '02', '03', '04', '05', '06', '07', '08', '09',
					'10', '11', '12'];

$SCS_MONTH_NAMES = { '01' => 'Jan',  '02' => 'Feb', '03' => 'Mar', 
					 '04' => 'Apr',  '05' => 'May', '06' => 'June', 
					 '07' => 'July', '08' => 'Aug', '09' => 'Sept', 
					 '10' => 'Oct',  '11' => 'Nov', '12' => 'Dec'};

$SCS_DAYS = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', 
			 '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', 
			 '23', '24', '25', '26', '27', '28', '29', '30', '31'];

$SCS_HOURS = ['00', '01', '02', '03', '04', '05', '06', '07', '08', '09', '10',
			  '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21',
			  '22', '23'];

$SCS_MINSEC = ['00', '01', '02', '03', '04', '05', '06', '07', '08', '09', '10',
			   '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21',
			   '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32',
			   '33', '34', '35', '36', '37', '38', '39', '40', '41', '42', '43',
			   '44', '45', '46', '47', '48', '49', '50', '51', '51', '53', '54',
			   '55', '56', '57', '58', '59' ];

1;
__END__
