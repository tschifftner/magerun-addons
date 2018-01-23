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
    protected $_projectConfig;

    /**
     * Setup arguments, options and description
     */
    protected function configure()
    {
        $this
            ->setName('project:helper:create')
            ->addArgument('project', InputArgument::OPTIONAL, 'Project name')
            ->addArgument('environment', InputArgument::OPTIONAL, 'Environment (devbox, staging, production, etc...)')
            ->addOption('bucket', null, InputOption::VALUE_OPTIONAL, 'Define s3 bucket of builds')
            ->addOption(
                'projectstorage', null, InputOption::VALUE_OPTIONAL,
                'Define projectstorage path (default is $HOME/projectstorage'
            )
            ->addOption(
                'root', null, InputOption::VALUE_OPTIONAL,
                'Define root folder path (default is $HOME/www/$project/$environment)'
            )
            ->addOption(
                'magentoRoot', null, InputOption::VALUE_OPTIONAL,
                'Define magento root folder path (default is $HOME/www/$project/$environment/releases/current/htdocs)'
            )
            ->addOption(
                'publicFolder', null, InputOption::VALUE_OPTIONAL,
                'Define public folder (default is htdocs)'
            )
            ->addOption('build_file', null, InputOption::VALUE_OPTIONAL, 'Build file name')
            ->setDescription('Create project helper');
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

        $moduleDir = __DIR__ . DIRECTORY_SEPARATOR;

        // require arguments
        $project = $this->getOrAskForArgument('project', $input, $output);
        $environment = $this->getOrAskForArgument('environment', $input, $output);

        if ( !$project ) {
            $output->writeln('<error>No project defined</error>');
            return;
        }

        if ( !$environment ) {
            $output->writeln('<error>No environment defined</error>');
            return;
        }

        $this->loadProjectConfig($config, $project, $environment);

        // define
        $bucket = $this->getProjectConfig('bucket', $this->getConfig('s3bucket'));
        $projectstorage = $this->getProjectConfig('projectstorage', '$HOME/projectstorage');
        $root = $this->getProjectConfig('root', "\$HOME/www/${project}/${environment}");
        $publicFolder = $this->getProjectConfig('publicFolder', 'htdocs');
        $magentoRoot = $this->getProjectConfig(
            'magentoRoot',
            "\$HOME/www/${project}/${environment}/releases/current/${publicFolder}"
        );
        $buildFile = $this->getConfig('build_file', "${bucket}/${project}/builds/${project}.tar.gz");

        if ( $input->getOption('bucket') ) {
            $bucket = $input->getOption('bucket');
        }

        if ( $input->getOption('projectstorage') ) {
            $projectstorage = $input->getOption('projectstorage');
        }

        if ( $input->getOption('root') ) {
            $root = $input->getOption('root');
        }

        if ( $input->getOption('build_file') ) {
            $buildFile = $input->getOption('build_file');
        }

        $replace = array(
            '${project}'        => $project,
            '${environment}'    => $environment,
            '${bucket}'         => $bucket,
            '${projectstorage}' => $projectstorage,
            '${root}'           => $root,
            '${publicFolder}'   => $publicFolder,
            '${magentoRoot}'    => $magentoRoot,
            '${buildFile}'      => $buildFile,
            '${hosts}'          => implode(" ", $this->getProjectConfig('hosts', ["${project}.local"])),

            '${createVhost}'      => $this->getProjectConfig('create_vhost', $this->getConfig('create_vhost')),
            '${databaseName}'     => $this->getProjectConfig('database/name'),
            '${databaseHost}'     => $this->getProjectConfig('database/host', '127.0.0.1'),
            '${databaseUsername}' => $this->getProjectConfig('database/username'),
            '${databasePassword}' => $this->getProjectConfig('database/password'),
        );

        if ( !$tpl = $this->getProjectConfig('apache_vhost_tpl') ) {
            $tpl = file_get_contents($moduleDir . 'apache-vhost.conf'); // @codingStandardsIgnoreLine
        }
        $replace['${vhostTpl}'] = $this->parseVariables($tpl, $replace);

        // Load template file
        $file = file_get_contents($moduleDir . 'MagentoHelper.sh'); // @codingStandardsIgnoreLine
        $file = $this->parseVariables($file, $replace);
        $this->saveFile("/usr/local/bin/$project-$environment", $file, 0755);

        $output->writeln("<info>Helper <comment>$project-$environment</comment> has been created/updated</info>");
    }

    /**
     * @param $config
     * @param $project
     * @param $environment
     * @return $this
     */
    public function loadProjectConfig($config, $project, $environment)
    {
        $configVariable = sprintf('%s_%s', $project, $environment);
        if ( isset($config[$configVariable]) ) {
            $this->_projectConfig = $config[$configVariable];
        }

        return $this;
    }

    /**
     * @param $key
     * @param null $default
     * @return mixed
     */
    public function getProjectConfig($key, $default = null)
    {
        $value = $this->getConfig($key, null, $this->_projectConfig);

        return $value ? $value : $this->getConfig($key, $default);
    }

    /**
     * @param $key
     * @param null $default
     * @param null $config
     * @return null
     */
    public function getConfig($key, $default = null, $config = null)
    {
        if ( is_null($config) ) {
            $config = $this->getApplication()->getConfig();
        }
        if ( false === strpos($key, '/') ) {
            return isset($config[$key]) ? $config[$key] : $default;
        }

        foreach (explode('/', $key) as $part) {
            if ( !isset($config[$part]) ) {
                return $default;
            }
            $config = $config[$part];
        }
        return $config;
    }

    /**
     * @param $path
     * @param $content
     * @param int $mode
     */
    public function saveFile($path, $content, $mode = 0755)
    {
        file_put_contents($path, $content); // @codingStandardsIgnoreLine
        chmod($path, $mode); // @codingStandardsIgnoreLine
    }

    /**
     * @param $string
     * @param $replace
     * @return mixed
     */
    public function parseVariables($string, $replace)
    {
        return str_replace(array_keys($replace), $replace, $string);
    }
}
