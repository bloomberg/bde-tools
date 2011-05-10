/* privgw.c  privilege gateway */

/* gstrauss1@bloomberg.net */

/* Solaris: cc -xO3 -DCSTOOLS_CSTEST -o cstest/robogw.solaris privgw.c */
/* AIX:     cc -O3  -DCSTOOLS_CSTEST -o cstest/robogw.aix     privgw.c */
/* Solaris: cc -xO3 -DCSTOOLS_ALPHA  -o alpha/robogw.solaris  privgw.c */
/* AIX:     cc -O3  -DCSTOOLS_ALPHA  -o alpha/robogw.aix      privgw.c */
/* Solaris: cc -xO3 -DCSTOOLS_BETA   -o beta/robogw.solaris   privgw.c */
/* AIX:     cc -O3  -DCSTOOLS_BETA   -o beta/robogw.aix       privgw.c */
/* Solaris: cc -xO3 -DCSTOOLS_LGOOD  -o lgood/robogw.solaris  privgw.c */
/* AIX:     cc -O3  -DCSTOOLS_LGOOD  -o lgood/robogw.aix      privgw.c */
/* Solaris: cc -xO3                  -o prod/robogw.solaris   privgw.c */
/* AIX:     cc -O3                   -o prod/robogw.aix       privgw.c */

/* For access to thread-safe system functions */
#define _REENTRANT 1
#define _THREAD_SAFE 1

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#ifndef PATH_MAX
  #ifdef MAXPATHLEN
    #define PATH_MAX MAXPATHLEN
  #else
    #define PATH_MAX 4096
  #endif
#endif

#ifdef __sun
  #include <netdb.h>     /* MAXHOSTNAMELEN */  /* Solaris */
#else
  #include <sys/param.h> /* MAXHOSTNAMELEN */  /* AIX, Linux, ... */
#endif
#ifndef MAXHOSTNAMELEN
  #error  MAXHOSTNAMELEN is not defined.  Please examine system header includes.
#endif

/* access log must be defined in a place that is safe to write */
#define ACCESS_LOG_FILE "/bb/csdata/logs/roboaccess.log"

/* path to authorization (whitelist/blacklist) script */

#if defined(CSTOOLS_CSTEST)  /* cstest */
  #define ACCESS_LOG_TAG "cstest"
  #define AUTHZ_PATH "/bbsrc/bin/cstest/bin"
#elif defined(CSTOOLS_ALPHA)  /* alpha */
  #define ACCESS_LOG_TAG "alpha"
  #define AUTHZ_PATH "/bbsrc/bin/alpha/bin"
#elif defined(CSTOOLS_BETA) /* beta */
  #define ACCESS_LOG_TAG "beta"
  #define AUTHZ_PATH "/bbsrc/bin/beta/bin"
#elif defined(CSTOOLS_LGOOD) /* last good */
  #define ACCESS_LOG_TAG "lgood"
  #define AUTHZ_PATH "/bbsrc/bin/lgood/bin"
#else                       /* production */
  #define ACCESS_LOG_TAG "prod"
  #define AUTHZ_PATH "/bbsrc/bin/prod/bin"
#endif

#define AUTHZ_CMD AUTHZ_PATH "/bde_script_authz.pl"

extern char **environ;

#define SAFE_ENV_SIZE 5
#define DEFAULT_CHANGE_GROUP "general"

static char suid_exec_path[PATH_MAX] = "SUID_EXECUTION_PATH=";

/* Note that only a specific set of environment variables are passed through
 * (explict allow; default deny)
 * This results in the omission of dangerous environment variables, as well
 * as variables such as TZ and LANG.  By not passing LANG, the default is the
 * C locale, i.e. LANG=C
 */
void
sanitize_env(const uid_t uid)
{
    struct passwd *pw;
    const char *group;
    /* allocations for items in environment must have lifetime of program */
    static char *safe_environ[SAFE_ENV_SIZE];
    static char safe_path[]   = "PATH=/bin:/usr/bin:/usr/local/bin";
    static char username[80]  = "CHANGE_USER=";
    static char groupname[80] = "CHANGE_GROUP=";
    int i;

    if ((pw = getpwuid(uid)) != NULL
	&& (strlen(username) + strlen(pw->pw_name)) < sizeof(username)) {
	/* (total length checked above; strncat() length param is too large) */
	strncat(username, pw->pw_name, sizeof(username));
    }
    else {
	exit(1);
    }

    if ((group = getenv("GROUP")) == NULL) {
	group = DEFAULT_CHANGE_GROUP;
    }
    if (strlen(groupname) + strlen(group) < sizeof(groupname)) {
	/* (total length checked above; strncat() length param is too large) */
	strncat(groupname, group, sizeof(groupname));
    }
    else {
	exit(1);
    }

    i = 0;
    safe_environ[i++] = safe_path;
    safe_environ[i++] = suid_exec_path;
    safe_environ[i++] = username;
    safe_environ[i++] = groupname;
    safe_environ[i++] = NULL;
    if (i > SAFE_ENV_SIZE) {
	abort();
    }

    environ = safe_environ;
}


void
sanitize_fds(void)
{
    struct stat st;
    if (fstat(STDIN_FILENO, &st) != 0
	&& (errno != EBADF || open("/dev/null", O_RDONLY) != STDIN_FILENO)) {
	exit(1);
    }
    if (fstat(STDOUT_FILENO, &st) != 0
	&& (errno != EBADF || open("/dev/null", O_WRONLY) != STDOUT_FILENO)) {
	exit(1);
    }
    if (fstat(STDERR_FILENO, &st) != 0
	&& (errno != EBADF || open("/dev/null", O_WRONLY) != STDERR_FILENO)) {
	exit(1);
    }
}


void
sanitize_signals(void)
{
    /* unblock all signals in the signal mask
     * (signal mask may be inherited from caller)
     * set SIGCHLD to default signal handler
     */
    sigset_t sigset;

    sigfillset(&sigset);
    if (sigprocmask(SIG_UNBLOCK, &sigset, NULL) != 0) {
	exit(1);
    }
    if (signal(SIGCHLD, SIG_DFL) == SIG_ERR) {
	exit(1);
    }
}


void
privgw_log_access(const char * const arg0, const char * const target_cmd)
{
    /* This routine is being called after sanitize_env() (at the time this
     * note was written) and so there is no LANG in the environment; LANG=C.
     */
    /* Since privileges have been dropped and real and effective uids reset by
     * this point, either pass uid as arg to this routine and do an extra
     * getpwuid(), or pull CHANGE_USER out of environment that we know we set
     * in sanitize_env().  This routine opts for the latter.
     */
    /* To be even more pedantic, use strnvis() from -lopenbsd-compat to make
     * the user-provided arg0 safe for viewing in logs (without cat -v or such)
     */
    char hostname[MAXHOSTNAMELEN+1];
    char datestr[25];
    const char *user = getenv("CHANGE_USER");
    FILE *logf;
    struct tm timeptr;
    time_t secs;

    if (user == NULL) { /* should not happen */
	user = "";
    }

    if (time(&secs) == (time_t)-1) {
	secs = 0;
    }
    gmtime_r(&secs, &timeptr);
    if (strftime(datestr,sizeof(datestr),"%Y.%m.%d-%H:%M:%S-GMT",&timeptr)==0){
	static const char deftime[] = "1970.01.01-00:00:00-GMT";
	if (sizeof(datestr) < sizeof(deftime)) { abort(); }  /* impossible */
	memcpy(datestr, deftime, sizeof(deftime));
    }

    if (gethostname(hostname, sizeof(hostname)) == 0) {
	hostname[sizeof(hostname)-1] = '\0'; /* ensure null termination */
    }
    else {
	#if MAXHOSTNAMELEN < 2
	#error MAXHOSTNAMELEN is too small
	#endif
	hostname[0] = '-';
	hostname[1] = '\0';
    }

    /* access log must be defined in a place that is safe to write */
    /* ignore error silently if unable to write to access log */
    if ((logf = fopen(ACCESS_LOG_FILE, "a")) != NULL) {
	fprintf(logf, "%s %s %s %s %s %s\n",
		datestr, hostname, user, ACCESS_LOG_TAG,
		target_cmd ? "exec" : "deny",
		target_cmd ? target_cmd : arg0);
	fclose(logf);
    }
}


#define SAFE_ARGV_SIZE 4

void
authz_exec(const uid_t uid, char *arg0)
{
    char *authz_argv[SAFE_ARGV_SIZE];
    char *tag;
    int i;
    char authz_cmd[] = AUTHZ_CMD;
    char uidstr[21];

    /* stringified uid */
    if (snprintf(uidstr, sizeof(uidstr), "%lu", (unsigned long)uid)
	  > sizeof(uidstr)-1) {
	exit(1);
    }

    /* basename() */
    if ((tag = strrchr(arg0, '/')) != NULL) {
	tag++;
    }
    else {
	tag = arg0;
    }

    i = 0;
    authz_argv[i++] = authz_cmd;
    authz_argv[i++] = uidstr;
    authz_argv[i++] = tag;
    authz_argv[i++] = NULL;
    if (i > SAFE_ARGV_SIZE) {
	abort();
    }

    /* set SUID_EXECUTION_PATH to dirname (empty if none) of authz_cmd */
    if (strlen(suid_exec_path) + strlen(AUTHZ_PATH) < sizeof(suid_exec_path)) {
	/* (total length checked above; strncat() length param is too large) */
	strncat(suid_exec_path, AUTHZ_PATH, sizeof(suid_exec_path));
    }

    execv(authz_cmd, authz_argv);
    exit(1);
}


char *
authz_check(const uid_t uid, char *arg0)
{
    pid_t pid;
    int filedes[2];

    if (pipe(filedes) != 0) {
	exit(1);
    }

    do { pid = fork(); } while (pid == -1 && errno == EAGAIN);

    if (pid == 0) {			/* child */

	if (dup2(filedes[1], STDOUT_FILENO) != -1
	    && close(filedes[0]) == 0 && close(filedes[1]) == 0) {

	    authz_exec(uid, arg0);	/* exits 0 upon success */
	}
	exit(1);

    }
    else if (pid != -1) {		/* parent */

	char *target_cmd;
	int rv;
	int status;
	ssize_t nbytes;
	ssize_t offset = 0;

	if (close(filedes[1]) != 0) {
	    exit(1);
	}
	if ((target_cmd = malloc(PATH_MAX)) == NULL) {
	    exit(1);
	}

	/* read AUTHZ_CMD program output */
	do {
	    nbytes = read(filedes[0], target_cmd+offset, PATH_MAX-offset-1);
	} while ((nbytes > 0 && (offset += nbytes) < PATH_MAX-1)
		 || (nbytes == -1 && errno == EINTR));
	target_cmd[offset] = '\0';
	close(filedes[0]);	/* (intentionally ignore return value) */
	if (nbytes == -1) {
	    exit(1);
	}

	/* reap child and return target command */
	do {
	    rv = waitpid(pid, &status, 0);
	} while (rv == -1 && errno == EINTR);

	if (rv == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
	    return target_cmd;	/* path returned from AUTHZ_CMD is trusted */
	}
	else {
	    privgw_log_access(arg0, NULL);  /* log access */
	    fputs("access denied\n", stderr);
	    exit(1);
	}
	exit(1);

    }
    else  {			/* error. (pid == -1) */
	exit(1);
    }
}


int
main(int argc, char *argv[]) 
{
    char *target_cmd;
    const uid_t uid = getuid();

    /* IMMEDIATELY drop privileges to become robocop.stage, if setuid root
     *
     * (AIX does not allow non-root to set ruid.  So when ssh uses keys of
     *  ruid (ssh is setuid root, and calling user ruid keys are used), the keys
     *  are not those of user 'robocop'.  Therefore, this privilege gateway C
     *  wrapper is now being run setuid root so that real and effective uids
     *  can be made "robocop")
     * (While we would prefer using setgroups(1, &pw->pw_gid) (to clear the
     *  supplemental group list) over using initgroups(), the tools using this
     *  wrapper need to interact with tools running under group "sibuild", 
     *  of which user "robocop" is a member via supplemental groups, and likely
     *  also need access as group "general")
     * (getgrnam, getpwnam, and initgroups use static memory structures and
     *  initgroups (and setgroups) has been known to step on these structures,
     *  so save info in temporary variables for use after initgroups())
     */
    if (geteuid() == 0) {
	struct group  * const gr = getgrnam("stage");
	struct passwd * const pw = getpwnam("robocop");
	const uid_t uid = (pw != NULL ? pw->pw_uid : 0);
	if (pw == NULL || gr == NULL
	    || setgid(gr->gr_gid) != 0
	    || initgroups("robocop",pw->pw_gid) != 0
	    || setuid(uid) != 0) {
	    fputs("access denied (error dropping root privileges)\n", stderr);
	    exit(1);
	}
    }
    /* If not setuid root, set ruid and rgid to euid and egid, or error out */
    else {
	const gid_t egid = getegid();
	const uid_t euid = geteuid();
	if (setregid(egid, -1) != 0 || setgid(egid) != 0 || getgid() != egid
	    || setreuid(euid, -1) != 0 && setuid(euid) != 0 || getuid() !=euid){
	    fputs("Access denied (error setting privileges)\n", stderr);
	    fputs("Please retry on a Solaris machine\n", stderr);
	    exit(1);
	}
    }

    /* replace the environment with a safe environment */
    sanitize_env(uid);

    /* make sure stdin, stdout, and stderr are open */
    sanitize_fds();

    /* set signal handlers to known state */
    sanitize_signals();

    /* check authorization and run target command */

    if (argc < 1) { abort(); } /*(should never happen)*/
    target_cmd = authz_check(uid, argv[0]);

    /* log access */
    privgw_log_access(argv[0], target_cmd);

    if (target_cmd != NULL) {

	/* set SUID_EXECUTION_PATH to dirname (empty if none) of target_cmd */
	char * const last_slash = rindex(target_cmd, '/');
	if (last_slash != NULL && last_slash != target_cmd
	    && (strlen(suid_exec_path) + (last_slash - target_cmd))
		< sizeof(suid_exec_path)) {
	    *last_slash = '\0';
	    /* (total length checked above; strncat() length param too large) */
	    strncat(suid_exec_path, target_cmd, sizeof(suid_exec_path));
	    *last_slash = '/';
	}

	argv[0] = target_cmd;
        execv(target_cmd, argv);
    }
    else {
	return 1;
    }

    return 1;
}
