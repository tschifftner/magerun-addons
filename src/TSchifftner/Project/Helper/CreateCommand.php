<?php

namespace TSchifftner\Project\Helper;

use N98\Magento\Application\ConfigurationLoader;
use N98\Magento\Command\AbstractMagentoCommand;
use N98\Util\OperatingSystem;
use N98\Magento\Application\ConfigFile;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Yaml\Yaml;
use InvalidArgumentException;

class CreateCommand extends AbstractMagentoCommand
{
    /**
     * Setup arguments, options and description
     */
    protected function configure()
    {
        $this
          ->setName('project:helper:create')
          ->addArgument('project', InputArgument::OPTIONAL, 'Project name')
          ->addArgument('environment', InputArgument::OPTIONAL, 'Environment (devbox, staging, production, etc...)')
          ->addOption('s3bucket', null, InputOption::VALUE_OPTIONAL, 'Define s3 bucket of builds')
          ->addOption('projectstorage', null, InputOption::VALUE_OPTIONAL, 'Define projectstorage path (default is $HOME/projectstorage')
          ->addOption('release_folder', null, InputOption::VALUE_OPTIONAL, 'Define release folder path (default is $HOME/www/$project/$environment/releases)')
          ->addOption('build_file', null, InputOption::VALUE_OPTIONAL, 'Build file name')
          ->setDescription('Create project helper')
        ;
    }



    /**
    * @param \Symfony\Component\Console\Input\InputInterface $input
    * @param \Symfony\Component\Console\Output\OutputInterface $output
    * @return int|void
    */
    protected function execute(InputInterface $input, OutputInterface $output)
    {
        // read config
        $config = $this->getApplication()->getConfig();

        // require arguments
        $project = $this->getOrAskForArgument('project', $input, $output);
        $environment = $this->getOrAskForArgument('environment', $input, $output);

        if( ! $project) {
            $output->writeln('<error>No project defined</error>');
            return;
        }

        if( ! $environment) {
            $output->writeln('<error>No environment defined</error>');
            return;
        }

        // define
        $s3bucket = isset($config['s3bucket']) ? $config['s3bucket'] : null;
        $projectstorage = isset($config['projectstorage']) ? $config['projectstorage'] : '$HOME/projectstorage';
        $releaseFolder = isset($config['release_folder']) ? $config['release_folder'] : "\$HOME/www/${project}/${environment}/releases";
        $buildFile = isset($config['build_file']) ? $config['build_file'] : "${s3bucket}/${project}/builds/${project}.tar.gz";

        if($input->getOption('s3bucket')) {
            $s3bucket = $input->getOption('project');
        }

        if($input->getOption('projectstorage')) {
            $projectstorage = $input->getOption('projectstorage');
        }

        if($input->getOption('release_folder')) {
            $releaseFolder = $input->getOption('release_folder');
        }

        if($input->getOption('build_file')) {
            $buildFile = $input->getOption('build_file');
        }


        // Load template file
        $file = file_get_contents(__DIR__ . DIRECTORY_SEPARATOR.'MagentoHelper.sh');

        $file = str_replace('${project}', $project, $file);
        $file = str_replace('${environment}', $environment, $file);
        $file = str_replace('${s3bucket}', $s3bucket, $file);
        $file = str_replace('${projectstorage}', $projectstorage, $file);
        $file = str_replace('${releaseFolder}', $releaseFolder, $file);
        $file = str_replace('${buildFile}', $buildFile, $file);


        $filepath = "/usr/local/bin/$project-$environment";
        file_put_contents($filepath, $file);
        chmod($filepath, 0755);

        $output->writeln("<info>Helper <comment>$project-$environment</comment> has been created/updated</info>");
    }
}
