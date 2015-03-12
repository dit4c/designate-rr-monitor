gulp = require('gulp')
coffeelint = require('gulp-coffeelint')
mocha = require('gulp-mocha')

handleError = (err) ->
  console.log(err.toString())
  this.emit('end')

gulp.task 'lint', () ->
  gulp.src('*.coffee')
    .pipe(coffeelint())
    .pipe(coffeelint.reporter('fail'))

gulp.task 'watch', ['default'], () ->
  gulp.watch '*.coffee', ['default']

gulp.task 'test', () ->
  gulp.src('test.coffee', {read: false})
    .pipe(mocha({reporter: 'spec'}))
    .on("error", handleError)

gulp.task 'default', ['test', 'lint']
