<#  Builds a synthetic solution .zip with a nested .msapp for end-to-end testing.
    Seeds known issues so we can verify the analyzer detects each one.
    Output: test/fixtures/SampleSolution.zip  (and a bare test/fixtures/FieldServiceApp.msapp) #>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$enc = New-Object System.Text.UTF8Encoding($false)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fix  = Join-Path $root 'fixtures'
$stage = Join-Path $root '_stage'
foreach ($d in @($fix,$stage)) { if (Test-Path $d) { Remove-Item -Recurse -Force $d }; New-Item -ItemType Directory -Path $d -Force | Out-Null }

# ---- Build the .msapp staging tree (Src + DataSources + CanvasManifest) ----
$app = Join-Path $stage 'msapp'
$src = Join-Path $app 'Src'
$ds  = Join-Path $app 'DataSources'
New-Item -ItemType Directory -Path $src,$ds -Force | Out-Null

function W($path,$text){ $d=Split-Path -Parent $path; if($d -and -not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}; [System.IO.File]::WriteAllText($path,$text,$enc) }

W (Join-Path $src 'App.pa.yaml') @'
App:
    Properties:
        StartScreen: =HomeScreen
        OnStart: |
            =Set(gblUser, User().FullName);
            ClearCollect(colOrders, Orders);
            ClearCollect(colCustomers, Customers);
            Set(unusedVar, 42);
            Navigate(HomeScreen, ScreenTransition.None)
'@

W (Join-Path $src 'HomeScreen.pa.yaml') @'
Screens:
    HomeScreen:
        Properties:
            OnVisible: =Set(gblCount, CountRows(colOrders))
        Children:
            - galOrders:
                Control: Gallery@2.3.0
                Properties:
                    Items: =Filter(Orders, Status = "Open")
            - Button2:
                Control: Classic/Button@2.2.0
                Properties:
                    OnSelect: =Navigate(DetailScreen, ScreenTransition.Cover)
                    Text: ="Go to details"
            - lblWelcome:
                Control: Label@2.0.0
                Properties:
                    Text: =Concatenate("Hello ", gblUser, " welcome to the application dashboard")
'@

W (Join-Path $src 'DetailScreen.pa.yaml') @'
Screens:
    DetailScreen:
        Children:
            - Gallery1:
                Control: Gallery@2.3.0
                Properties:
                    Items: =Orders
                    OnSelect: =ForAll(colOrders, LookUp(Customers, Id = ThisRecord.CustId))
            - btnSave:
                Control: Classic/Button@2.2.0
                Properties:
                    OnSelect: =Patch(Orders, Defaults(Orders), {Title: "x"})
            - lblSame:
                Control: Label@2.0.0
                Properties:
                    Text: =Concatenate("Hello ", gblUser, " welcome to the application dashboard")
'@

W (Join-Path $src 'OrphanScreen.pa.yaml') @'
Screens:
    OrphanScreen:
        Children:
            - lblOrphan:
                Control: Label@2.0.0
                Properties:
                    Text: ="Nobody navigates here"
'@

W (Join-Path $ds 'Orders.json')    '{"Name":"Orders","Type":"Table","ApiId":"/providers/microsoft.powerapps/apis/shared_sharepointonline"}'
W (Join-Path $ds 'Customers.json') '{"Name":"Customers","Type":"Table","ApiId":"/providers/microsoft.powerapps/apis/shared_sharepointonline"}'
W (Join-Path $ds 'Archive.json')   '{"Name":"Archive","Type":"Table","ApiId":"/providers/microsoft.powerapps/apis/shared_sharepointonline"}'
W (Join-Path $app 'CanvasManifest.json') '{"Properties":{"Name":"FieldServiceApp"}}'

# ---- Zip the .msapp ----
$msapp = Join-Path $fix 'FieldServiceApp.msapp'
[System.IO.Compression.ZipFile]::CreateFromDirectory($app, $msapp)

# ---- Build solution tree mimicking `pac solution unpack`: canvasapps/<schema>/ ----
$sol = Join-Path $stage 'solution'
$canv = Join-Path $sol 'canvasapps\fieldservice_app_documents'
New-Item -ItemType Directory -Path $canv -Force | Out-Null
Copy-Item $msapp (Join-Path $canv 'FieldServiceApp.msapp')
W (Join-Path $sol 'solution.xml') '<ImportExportXml><SolutionManifest><UniqueName>SampleSolution</UniqueName></SolutionManifest></ImportExportXml>'
$solzip = Join-Path $fix 'SampleSolution.zip'
[System.IO.Compression.ZipFile]::CreateFromDirectory($sol, $solzip)

# ---- Also a zero-app solution and a legacy (no Src) msapp for branch testing ----
$noapp = Join-Path $stage 'noapp'; New-Item -ItemType Directory -Path $noapp -Force | Out-Null
W (Join-Path $noapp 'workflows\flow1.json') '{"name":"just a flow"}'
[System.IO.Compression.ZipFile]::CreateFromDirectory($noapp, (Join-Path $fix 'NoAppSolution.zip'))

$legacy = Join-Path $stage 'legacy'; New-Item -ItemType Directory -Path $legacy -Force | Out-Null
W (Join-Path $legacy 'Controls\1.json') '{"old":"format"}'
W (Join-Path $legacy 'CanvasManifest.json') '{"Properties":{"Name":"LegacyApp"}}'
[System.IO.Compression.ZipFile]::CreateFromDirectory($legacy, (Join-Path $fix 'LegacyApp.msapp'))

# ---- A two-app solution for the multiple-apps branch ----
$multi = Join-Path $stage 'multi'
New-Item -ItemType Directory -Path (Join-Path $multi 'canvasapps\app_one'),(Join-Path $multi 'canvasapps\app_two') -Force | Out-Null
Copy-Item $msapp (Join-Path $multi 'canvasapps\app_one\AppOne.msapp')
Copy-Item $msapp (Join-Path $multi 'canvasapps\app_two\AppTwo.msapp')
[System.IO.Compression.ZipFile]::CreateFromDirectory($multi, (Join-Path $fix 'MultiAppSolution.zip'))

# ---- MaintainabilityKitchenSink: planted, known-count fixture (grown per detector) ----
$ks = Join-Path $stage 'ks'; $ksSrc = Join-Path $ks 'Src'; $ksComp = Join-Path $ksSrc 'Components'; $ksDs = Join-Path $ks 'DataSources'
New-Item -ItemType Directory -Path $ksComp,$ksDs -Force | Out-Null
W (Join-Path $ksSrc 'App.pa.yaml') @'
App:
    Properties:
        StartScreen: =MainScreen
        OnStart: |
            =Set(gblZebra, 1);
            Set(gblApple, 2);
            Set(gblTitle, "Kitchen Sink");
            Set(gblMango, 3);
            ClearCollect(colZebra, [1]);
            ClearCollect(colApple, [2])
'@
W (Join-Path $ksSrc 'MainScreen.pa.yaml') @'
Screens:
    MainScreen:
        Children:
            - lblZebra:
                Control: Label@2.0.0
                Properties:
                    Text: =gblZebra
            - lblApple:
                Control: Label@2.0.0
                Properties:
                    Text: =gblApple
            - lblTitle:
                Control: Label@2.0.0
                Properties:
                    Text: =gblTitle
            - lblCollections:
                Control: Label@2.0.0
                Properties:
                    Text: =CountRows(colZebra) + CountRows(colApple)
            - conOuter:
                Control: GroupContainer@1.3.0
                Children:
                    - conInner:
                        Control: GroupContainer@1.3.0
                        Children:
                            - lblDeep:
                                Control: Label@2.0.0
                                Properties:
                                    Text: ="deep"
            - lblBusy:
                Control: Label@2.0.0
                Properties:
                    Text: =If(gblBusy, "Working...", "")
            - btnSubmit:
                Control: Classic/Button@2.2.0
                Properties:
                    OnSelect: |
                        =// Submit the order to the back end
                        Set(gblBusy, true);
                        // Patch(Orders, Defaults(Orders), {Title: "x"});
                        Notify("done")
            - cmpFooterInstance:
                Control: cmpFooter
                Properties:
                    FooterText: ="hi"
            - btnStub:
                Control: Classic/Button@2.2.0
                Properties:
                    OnSelect: =false
                    Text: ="stub"
            - lblHidden:
                Control: Label@2.0.0
                Properties:
                    Visible: =false
                    Text: ="never shown"
            - lblDynamic:
                Control: Label@2.0.0
                Properties:
                    Visible: =gblTitle <> ""
                    Text: ="maybe shown"
            - lblDead:
                Control: Label@2.0.0
                Properties:
                    Text: =If(false, "never", "always")
            - lblLive:
                Control: Label@2.0.0
                Properties:
                    Text: =If(gblTitle <> "", "has title", "no title")
            - lblDupeA:
                Control: Label@2.0.0
                Properties:
                    Color: =RGBA(0, 0, 0, 1)
                    Size: =15
                    Text: ="Same content"
            - lblDupeB:
                Control: Label@2.0.0
                Properties:
                    Color: =RGBA(0, 0, 0, 1)
                    Size: =15
                    Text: ="Same content"
            - lblDifferent:
                Control: Label@2.0.0
                Properties:
                    Color: =RGBA(0, 0, 0, 1)
                    Size: =20
                    Text: ="Other content"
            - lblAnchor:
                Control: Label@2.0.0
                Properties:
                    Text: ="anchor"
            - lblAnchorRef:
                Control: Label@2.0.0
                Properties:
                    Text: =lblAnchor.Text
            - lblLong:
                Control: Label@2.0.0
                Properties:
                    Text: =Concatenate("This is a deliberately very long formula used to exercise the long-formula detector. ", "It needs to exceed the configured byte threshold so the LF detector fires on exactly this one control. ", "Padding padding padding padding padding padding padding padding padding padding.")
            - lblComplexNoComment:
                Control: Label@2.0.0
                Properties:
                    Text: =If (gblTitle = "a", 1, If (gblTitle = "b", 2, If (gblTitle = "c", 3, If (gblTitle = "d", 4, 5))))
            - lblNdA:
                Control: Label@2.0.0
                Properties:
                    Text: =If(gblUser <> "" && gblTitle <> "", Concatenate(gblUser, " - ", gblTitle, " - ", "main dashboard view - active"), Concatenate("Guest", " - ", "main dashboard view - inactive"))
            - lblNdB:
                Control: Label@2.0.0
                Properties:
                    Text: =If(gblUser <> "" && gblTitle <> "", Concatenate(gblUser, " - ", gblTitle, " - ", "main homepage view - active"), Concatenate("Guest", " - ", "main homepage view - inactive"))
'@
W (Join-Path $ksComp 'cmpHeader.pa.yaml') @'
ComponentDefinitions:
    cmpHeader:
        Type: CanvasComponent
        CustomProperties:
            HeaderText:
                PropertyKind: Input
                DataType: Text
        Children:
            - lblHeader:
                Control: Label@2.0.0
                Properties:
                    Text: =cmpHeader.HeaderText
'@
W (Join-Path $ksComp 'cmpFooter.pa.yaml') @'
ComponentDefinitions:
    cmpFooter:
        Type: CanvasComponent
        CustomProperties:
            FooterText:
                PropertyKind: Input
                DataType: Text
            UnusedProp:
                PropertyKind: Input
                DataType: Text
        Children:
            - lblFooter:
                Control: Label@2.0.0
                Properties:
                    Text: =cmpFooter.FooterText
'@
W (Join-Path $ksDs 'Orders.json') '{"Name":"Orders","Type":"Table","ApiId":"/providers/microsoft.powerapps/apis/shared_sharepointonline"}'
W (Join-Path $ks 'CanvasManifest.json') '{"Properties":{"Name":"MaintainabilityKitchenSink"}}'
[System.IO.Compression.ZipFile]::CreateFromDirectory($ks, (Join-Path $fix 'MaintainabilityKitchenSink.msapp'))

Remove-Item -Recurse -Force $stage
Get-ChildItem $fix | ForEach-Object { $_.Name }
