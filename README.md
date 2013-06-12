Android Examples translated to Eclipse Xtend
========================

This repository contains Android examples translated to [Eclipse Xtend](http://xtend-lang.org). 
Xtend is a statically typed alternative to Java which runs without additional overhead on Android.
It is much more expressive than Java and allows for much more readable and concise code.

###Getting Started

 - Download the Android Development Kit from http://developer.android.com/sdk/index.html
 - Use the update manager to install Xtend (updatesite : https://extern.itemis.de/jenkins/job/xtext-head/lastSuccessfulBuild/artifact/xtext.p2.repository/)
 - Clone thie repository and import the projects using the Import wizard for existing projects from within Eclipse.


###General Tips To Configure Your Existing Android Project

#### Adding The Xtend Libs 

Xtend uses Google Guava which you propably already use for Java development. In order to add the libs you need 
to copy the respective jars into the libs folder. Just as in the example projects.

#### Debugging

By default Xtend uses a debugging mode, which is not supported by DalvikVM. To debug on DalvikVM you need to change the
compiler settings in the project settings (use the option that mentions Android).

#### Generated Source Folder

By default xtend generates Java code into the folder 'xtend-gen'. As Android already contains a folder for generated Java source
it's a good idea to reuse that. You'll fid that setting the project's compiler settings as well.

#### Reorder Builders

If you experience strange compile errors during a clean build, the order of the Eclipse builders is not correct.
Make sure that first the Android builder runs, than the Xtext one and then the Java one.

For any problems or questions please visit [the google group for Xtend](https://groups.google.com/forum/?fromgroups#!forum/xtend-lang)
