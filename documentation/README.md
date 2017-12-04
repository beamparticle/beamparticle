## Documentation


## How to Build

> The python-sphinx package in ubuntu might be old
> considering the version of the ubuntu running on
> the system. So it is better to install sphinx via
> pip, which will always get the latest.
> If an older version of sphinx is installed (<1.3)
> then the build will fail.

We need platuml for generating flow diagram for requirements
which is generated via sphinxcontrib-needs.

    sudo apt-get install plantuml

Install sphinx and erlangdomain plugin as follows:

    sudo pip install sphinx
    sudo pip install sphinxcontrib-erlangdomain
    sudo pip install sphinx-git
    sudo pip install sphinxcontrib-needs sphinxcontrib-plantuml
    sudo pip install sphinx sphinx-autobuild sphinx_rtd_theme
    sudo pip install sphinxcontrib-phpdomain
    sudo pip install javasphinx

Now you can run make in the current folder.

    make html

The output will be generated in build/html.

