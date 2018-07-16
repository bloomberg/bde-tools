pipeline {

    agent {
        label 'BLDLNX'
    }

    options {
        disableConcurrentBuilds()                           // this job never build concurrently
        buildDiscarder(logRotator(numToKeepStr: '15'))      // log rotation setting, only keeping 15 builds
        skipDefaultCheckout()                               // skips default checkout of this repo.
    }

    stages {                                                //stages
        stage('Checkout') {
            steps {
                echo "checking out repository"              //checkout current repository
                checkout scm
            }
        }
        stage('Build') {
            steps {
                sh """
                    pwd
                    echo $BRANCH_NAME
                    ls -l 
                    source /bb/bde/documentation/sphinx_env/bin/activate
                    (cd docs; make html)
                    ls -l docs/build
                """
            }
        }
        stage('Deploy') {
            steps {
                sh "mkdir deploy"
                dir("deploy") {
                    sh """
                        pwd
                        ls
                    """
                }
            }
        }
    }

    post {                                                  // after the build, clean up workspace.
        always {
            echo 'Cleaning up the workspace after build....'
            deleteDir()
        }
        failure {
                    mail bcc: '',
                    cc: '',
                    replyTo: '',
                    from: 'bdebuild@bde.dev.bloomberg.com',
                    to: 'osubbotin@bloomberg.net',
                    subject: 'Build status of job :'+ env.JOB_NAME,
                    body: env.BUILD_URL + ' Failed!'
        }
    }
}
