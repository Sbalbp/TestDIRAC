"""
This program tests the correct addition and removal of components to the InstalledComponentsDB, as well as the components
CLI functions are used to ensure the test is as similar as possible to a real user-to-cli interaction
This test assumes that there is a DIRAC master server running on the local machine
This test assumes that the Notification service is not installed
This test assumes that the FTSDB database is not installed and doesn't exist in MySQL
"""

from DIRAC.Core.Base.Script import parseCommandLine
from DIRAC.Core.Utilities.CFG import CFG
parseCommandLine()

import unittest

from DIRAC.Core.Utilities.ComponentInstaller import gComponentInstaller
from DIRAC.ConfigurationSystem.Client.CSAPI import CSAPI
from DIRAC.FrameworkSystem.Client.ComponentMonitoringClient import ComponentMonitoringClient
from DIRAC.FrameworkSystem.Client.SystemAdministratorClientCLI import SystemAdministratorClientCLI
from DIRAC.Core.Security.ProxyInfo import getProxyInfo
from DIRAC.ConfigurationSystem.Client.Helpers.Registry import getUsernameForDN

class TestComponentInstallation( unittest.TestCase ):
  """
  Contains methods for testing of separate elements
  """

  def setUp( self ):
    self.host = 'localhost'
    self.notificationPort = 9154
    self.rootPwd = ''
    self.csClient = CSAPI()
    self.monitoringClient = ComponentMonitoringClient()
    self.client = SystemAdministratorClientCLI( self.host )

    self.csClient.downloadCSData()
    result = self.csClient.getCurrentCFG()
    if not result[ 'OK' ]:
      raise Exception( result[ 'Message' ] )
    cfg = result[ 'Value' ]

    setup = cfg.getOption( 'DIRAC/Setup' )

    self.frameworkSetup = cfg.getOption( 'DIRAC/Setups/' + setup + '/Framework' )
    self.rootPwd = cfg.getOption( 'Systems/Databases/Password' )
    self.diracPwd = self.rootPwd

    result = getProxyInfo()
    if not result[ 'OK' ]:
      raise Exception( result[ 'Message' ] )
    chain = result[ 'Value' ][ 'chain' ]
    result = chain.getCertInChain( -1 )
    if not result[ 'OK' ]:
      raise Exception( result[ 'Message' ] )
    result = result[ 'Value' ].getSubjectDN()
    if not result[ 'OK' ]:
      raise Exception( result[ 'Message' ] )
    userDN = result['Value']
    result = getUsernameForDN( userDN )
    if not result[ 'OK' ]:
      raise Exception( result[ 'Message' ] )
    self.user = result[ 'Value' ]
    if not self.user:
      self.user = 'unknown'

  def tearDown( self ):
    pass

class ComponentInstallationChain( TestComponentInstallation ):

  def testComponent( self ):

    # Install component
    self.client.do_install( 'service Framework Notification' )
    self.csClient.downloadCSData()


    # Check installation in CS
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification/' ) and cfg.isOption( 'Systems/Framework/' + self.frameworkSetup + '/URLs/Notification' ) )

    self.assert_( cfg.getOption( 'Systems/Framework/' + self.frameworkSetup + '/URLs/Notification' ) == 'dips://' + self.host + ':' + str( self.notificationPort ) + '/Framework/Notification' )

    # Check installation in database
    result = self.monitoringClient.getInstallations( { 'Instance': 'Notification', 'UnInstallationTime': None, 'InstalledBy': self.user },
                                                      { 'System': 'Framework', 'Type': 'service', 'Module': 'Notification' },
                                                      {}, False )

    self.assert_( result[ 'OK' ] and len( result[ 'Value' ] ) == 1 )

    # Install second component
    self.client.do_install( 'service Framework Notification2 -m Notification' )

    # Check installation in CS
    self.csClient.downloadCSData()
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification2/' ) and not cfg.isOption( 'Systems/Framework/' + self.frameworkSetup + '/URLs/Notification2' ) )

    # Uninstall component
    self.client.do_uninstall( '-f Framework Notification' )

    # Check CS is intact ( there is still one instance of Notification )
    self.csClient.downloadCSData()
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification/' ) and cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification/' ) and cfg.isOption( 'Systems/Framework/' + self.frameworkSetup + '/URLs/Notification' ) )

    # Uninstall component
    self.client.do_uninstall( '-f Framework Notification2' )

    # Check uninstallation in CS
    self.csClient.downloadCSData()
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( not cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification/' ) and not cfg.isSection( 'Systems/Framework/' + self.frameworkSetup + '/Services/Notification2/' ) and not cfg.isOption( 'Systems/Framework/' + self.frameworkSetup + '/URLs/Notification' ) )

  def testDatabase( self ):
    results = []

    gComponentInstaller.setMySQLPasswords( self.rootPwd, self.diracPwd )


    # Install database
    self.client.do_install( 'db FTSDB' )

    # Check installation in CS
    self.csClient.downloadCSData()
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( cfg.isSection( 'Systems/DataManagement/' + self.frameworkSetup + '/Databases/FTSDB/' ) )

    # Check in database
    result = self.monitoringClient.getInstallations( { 'Instance': 'FTSDB', 'UnInstallationTime': None, 'InstalledBy': self.user },
                                                      { 'System': 'DataManagement', 'Type': 'DB', 'Module': 'FTSDB' },
                                                      {}, False )
    self.assert_( result[ 'OK' ] and len( result[ 'Value' ] ) == 1 )

    # Uninstall database
    self.client.do_uninstall( 'db FTSDB' )

    # Check uninstallation in CS
    self.csClient.downloadCSData()
    cfg = self.csClient.getCurrentCFG()[ 'Value' ]
    self.assert_( not cfg.isSection( 'Systems/DataManagement/' + self.frameworkSetup + '/Databases/FTSDB/' ) )

if __name__ == '__main__':
  suite = unittest.defaultTestLoader.loadTestsFromTestCase( TestComponentInstallation )
  suite.addTest( unittest.defaultTestLoader.loadTestsFromTestCase( ComponentInstallationChain ) )
  testResult = unittest.TextTestRunner( verbosity = 2 ).run( suite )
