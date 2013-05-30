module.exports = (grunt) ->
  grunt.initConfig
    clean: ['lib']
    coffee:
      compile:
        expand: true 
        src: ['src/**/*.coffee', 'test/**/*.coffee', 'coverage/**/*.coffee']
        dest: 'lib'
        ext: '.js'
    mochaTest:
      test:
        options: 
          reporter: 'spec'
          require: 'lib/coverage/blanket'
        src: ['lib/test/**/*.js']
      report:
        options: 
          reporter: 'html-cov'
          quiet: true
        src: ['lib/test/**/*.js']
        dest: 'coverage.html'
      coverage:
        options:
          reporter: 'travis-cov'
        src: ['lib/test/**/*.js']

  grunt.loadNpmTasks 'grunt-contrib-clean'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-mocha-test'

  grunt.registerTask 'build', [
    'clean'
    'coffee'
  ]

  grunt.registerTask 'default', [
    'build'
    'mochaTest'
  ]